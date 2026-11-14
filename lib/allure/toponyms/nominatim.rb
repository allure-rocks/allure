# frozen_string_literal: true

require "json"
require "net/http"
require "timeout"
require "uri"

module Allure
  module Toponyms
    # Thin Nominatim reverse-geocoding client for route context.
    #
    # Framework-independent: Net::HTTP only, no Active Record and no Rails.
    # Unmapped places return nil; provider and transport failures are retryable.
    class Nominatim
      class UnavailableError < StandardError; end

      USER_AGENT = "Allure (toponymic markers; https://geocoding.allure.rocks)"
      MARKER_ZOOM = 14
      LOCALITY_ZOOM = 15
      ROUTE_ZOOM = 16
      SUMMIT_ZOOM = 18
      CENTER_SEARCH_RADIUS_METRES = 10_000.0
      SEARCH_LIMIT = 5
      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 10
      TOTAL_TIMEOUT = 15
      MAX_RESPONSE_BYTES = 256 * 1024

      attr_reader :base_url

      ADDRESS_KIND = {
        "isolated_dwelling" => "isolated_dwelling",
        "croft" => "isolated_dwelling",
        "locality" => "locality",
        "neighbourhood" => "neighbourhood",
        "quarter" => "neighbourhood",
        "suburb" => "suburb",
        "hamlet" => "hamlet",
        "village" => "village",
        "town" => "town",
        "city" => "city",
        "municipality" => "municipality",
        "county" => "county",
        "state" => "state",
        "region" => "state"
      }.freeze

      KIND_BY_ADDRESSTYPE = {
        "peak" => "summit",
        "saddle" => "pass",
        "mountain_pass" => "pass",
        "isolated_dwelling" => "isolated_dwelling",
        "locality" => "locality",
        "neighbourhood" => "neighbourhood",
        "quarter" => "neighbourhood",
        "suburb" => "suburb",
        "hamlet" => "hamlet",
        "city" => "city",
        "town" => "town",
        "village" => "village",
        "alpine_hut" => "hut",
        "road" => "route"
      }.freeze

      KIND_BY_CLASS_TYPE = {
        %w[natural peak] => "summit",
        %w[natural mountain_peak] => "summit",
        %w[natural saddle] => "pass",
        %w[place mountain_pass] => "pass",
        %w[place isolated_dwelling] => "isolated_dwelling",
        %w[place locality] => "locality",
        %w[place neighbourhood] => "neighbourhood",
        %w[place quarter] => "neighbourhood",
        %w[place suburb] => "suburb",
        %w[place hamlet] => "hamlet",
        %w[tourism alpine_hut] => "hut",
        %w[tourism wilderness_hut] => "hut",
        %w[tourism viewpoint] => "viewpoint",
        %w[natural waterfall] => "waterfall",
        %w[natural spring] => "spring",
        %w[natural cave_entrance] => "cave",
        %w[historic castle] => "landmark",
        %w[historic fort] => "landmark",
        %w[historic fortification] => "landmark",
        %w[historic monument] => "landmark",
        %w[historic memorial] => "landmark",
        %w[military fortification] => "landmark"
      }.freeze

      SETTLEMENT_KINDS = Settlements::KINDS

      def initialize(base_url:)
        @base_url = base_url
      end

      # Returns a normalized feature plus every useful address-hierarchy level.
      def reverse(longitude:, latitude:, zoom: MARKER_ZOOM)
        json = get("/reverse", lon: longitude, lat: latitude, format: "jsonv2", addressdetails: 1, zoom:)
        return nil unless json.is_a?(Hash)

        hierarchy = hierarchy(json.fetch("address", {}))
        feature = feature(json, hierarchy)
        return nil if feature.nil? && hierarchy.empty?

        { feature:, hierarchy: }
      end

      # Resolves a hierarchy-only settlement to a provider centroid. The viewbox
      # keeps common names tied to the route passage that produced the candidate.
      def settlement_center(name:, kind:, longitude:, latitude:, ancestors: [])
        latitude_delta = CENTER_SEARCH_RADIUS_METRES / 111_320.0
        longitude_delta = latitude_delta / [ Math.cos(latitude.to_f * Math::PI / 180.0).abs, 0.1 ].max
        viewbox = [
          longitude.to_f - longitude_delta, latitude.to_f + latitude_delta,
          longitude.to_f + longitude_delta, latitude.to_f - latitude_delta
        ].join(",")
        rows = get(
          "/search",
          q: ([ name ] + Array(ancestors).first(2)).join(", "),
          format: "jsonv2",
          addressdetails: 1,
          featureType: "settlement",
          bounded: 1,
          viewbox:,
          limit: 5
        )
        return nil unless rows.is_a?(Array)

        matches = rows.filter_map do |row|
          next unless row.is_a?(Hash) && same_name?(row["name"], name)

          row_kind = KIND_BY_ADDRESSTYPE[row["addresstype"].to_s] || kind_by_class_type(row)
          next unless SETTLEMENT_KINDS.include?(row_kind)

          normalized_center(row)&.merge(kind: row_kind, place_feature: row["category"] == "place")
        end
        preferred = matches.select { it.fetch(:kind) == kind.to_s }
        candidates = preferred.empty? ? matches : preferred
        candidates.min_by do |center|
          [ center.fetch(:place_feature) ? 0 : 1,
            Distance.metres(latitude.to_f, longitude.to_f, center.fetch(:center_latitude), center.fetch(:center_longitude)) ]
        end&.slice(:center_latitude, :center_longitude)
      end

      # Forward search for a place the owner types (privacy-zone editor). One
      # request per explicit search: the public Nominatim usage policy forbids
      # autocomplete, so callers never send one per keystroke.
      def search(query:, language: nil, limit: SEARCH_LIMIT)
        params = { q: query, format: "jsonv2", addressdetails: 0, limit: }
        params[:"accept-language"] = language if language
        rows = get("/search", params)
        return [] unless rows.is_a?(Array)

        rows.filter_map do |row|
          next unless row.is_a?(Hash)

          label = row["display_name"].to_s.strip
          center = normalized_center(row)
          next if label.empty? || center.nil?

          { label:, latitude: center.fetch(:center_latitude), longitude: center.fetch(:center_longitude) }
        end.uniq { it.fetch(:label) }.first(limit)
      end

      private

      def kind_by_class_type(row)
        category = row["category"] || row["class"]
        KIND_BY_CLASS_TYPE[[ category.to_s, row["type"].to_s ]]
      end

      def feature(json, hierarchy)
        name = json["name"].to_s.strip
        kind = KIND_BY_ADDRESSTYPE[json["addresstype"].to_s] || kind_by_class_type(json)
        return nil if name.empty? || kind.nil?

        {
          name:,
          kind:,
          importance: json["importance"].to_f,
          ancestors: hierarchy.map { it.fetch(:name) }.reject { same_name?(it, name) },
          osm_type: json["osm_type"],
          osm_id: json["osm_id"]
        }.merge(normalized_center(json) || {})
      end

      def hierarchy(address)
        entries = ADDRESS_KIND.filter_map do |key, kind|
          name = address[key].to_s.strip
          { name:, kind: } unless name.empty?
        end.uniq { normalized_name(it.fetch(:name)) }

        entries.each_with_index.map do |entry, index|
          entry.merge(ancestors: entries.drop(index + 1).map { it.fetch(:name) })
        end
      end

      def same_name?(left, right)
        normalized_name(left) == normalized_name(right)
      end

      def normalized_name(name)
        I18n.transliterate(name.to_s).downcase.strip
      end

      def normalized_center(row)
        latitude = Float(row["lat"], exception: false)
        longitude = Float(row["lon"], exception: false)
        return unless latitude&.finite? && longitude&.finite?
        return unless latitude.between?(-90, 90) && longitude.between?(-180, 180)

        { center_latitude: latitude, center_longitude: longitude }
      end

      def get(path, params)
        uri = URI.join("#{base_url}/", path.delete_prefix("/"))
        uri.query = URI.encode_www_form(params)
        request = Net::HTTP::Get.new(uri)
        request["User-Agent"] = USER_AGENT
        request["Accept"] = "application/json"

        body = +""
        Timeout.timeout(TOTAL_TIMEOUT) do
          Net::HTTP.start(
            uri.hostname, uri.port,
            use_ssl: uri.scheme == "https",
            open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT
          ) do |http|
            http.request(request) do |response|
              return nil if response.is_a?(Net::HTTPClientError) && response.code != "429"
              raise UnavailableError, "Geocoding provider returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

              response.read_body do |chunk|
                raise UnavailableError, "Geocoding response exceeds size limit" if body.bytesize + chunk.bytesize > MAX_RESPONSE_BYTES

                body << chunk
              end
            end
          end
        end

        JSON.parse(body)
      rescue UnavailableError
        raise
      rescue StandardError => error
        raise UnavailableError, error.message
      end
    end
  end
end
