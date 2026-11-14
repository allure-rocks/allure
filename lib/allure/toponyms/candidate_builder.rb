# frozen_string_literal: true

module Allure
  module Toponyms
    # Turns reverse-geocoding results into route passages. A place seen at
    # several consecutive samples is one candidate positioned near the middle
    # of that passage, not several competing labels.
    class CandidateBuilder
      ENDPOINT_FALLBACK_KINDS = %w[village hamlet locality isolated_dwelling municipality suburb neighbourhood].freeze
      ENDPOINT_BROAD_KINDS = %w[city town village municipality].freeze
      ENDPOINT_LOCAL_MAX_DISTANCE = 30_000.0
      FEATURE_KINDS = %w[
        pass summit landmark hut route viewpoint waterfall spring cave city town village hamlet locality
        isolated_dwelling suburb neighbourhood
      ].freeze

      def initialize(samples:, results:)
        @samples = samples
        @results = results
      end

      def call
        occurrences = @samples.zip(@results).each_with_index.flat_map do |(sample, result), sample_index|
          next [] unless result.is_a?(Hash)

          places(result).map do |place|
            place.merge(
              distance: sample.fetch(:distance),
              elevation: sample[:elevation],
              route_latitude: sample[:latitude],
              route_longitude: sample[:longitude],
              climb_summit: sample[:role] == "climb_summit",
              sample_index:
            )
          end
        end

        occurrences
          .group_by { [ normalize(it.fetch(:name)), it.fetch(:kind) ] }
          .values
          .flat_map { passages(it) }
          .map { build_candidate(it) }
          .sort_by { [ it.fetch(:distance), it.fetch(:name) ] }
      end

      # `centers` carries the resolved settlement centroids as
      # `{ name:, kind:, latitude:, longitude: }`; the endpoint adjudication
      # compares them to the provider's own feature.
      def route_context(total_distance:, centers: [])
        index = center_index(centers)
        {
          start: endpoint_label(@results.first, total_distance:, centers: index, point: @samples.first),
          finish: endpoint_label(@results.last, total_distance:, centers: index, point: @samples.last)
        }
      end

      private

      def places(result)
        values = []
        feature = result[:feature] || result["feature"]
        values << symbolize(feature) if feature.is_a?(Hash) && feature_kind?(feature)
        values.concat(Array(result[:hierarchy] || result["hierarchy"]).filter_map do |entry|
          symbolize(entry) if entry.is_a?(Hash)
        end)

        values
          .select { it[:name].to_s.strip.present? && it[:kind].to_s.present? }
          .uniq { [ normalize(it.fetch(:name)), it.fetch(:kind) ] }
      end

      def feature_kind?(feature)
        FEATURE_KINDS.include?((feature[:kind] || feature["kind"]).to_s)
      end

      def build_candidate(occurrences)
        ordered = occurrences.sort_by { it.fetch(:distance) }
        midpoint = (ordered.first.fetch(:distance) + ordered.last.fetch(:distance)) / 2.0
        representative = ordered.min_by { (it.fetch(:distance) - midpoint).abs }
        centered = ordered.find { it[:center_latitude].is_a?(Numeric) && it[:center_longitude].is_a?(Numeric) }
        ancestors = ordered.flat_map { Array(it[:ancestors]) }.compact.uniq

        {
          name: representative.fetch(:name),
          kind: representative.fetch(:kind),
          distance: representative.fetch(:distance),
          elevation: representative[:elevation],
          route_latitude: representative[:route_latitude],
          route_longitude: representative[:route_longitude],
          center_latitude: centered&.dig(:center_latitude),
          center_longitude: centered&.dig(:center_longitude),
          importance: ordered.filter_map { it[:importance] }.max.to_f,
          passage_start: ordered.first.fetch(:distance),
          passage_finish: ordered.last.fetch(:distance),
          coverage: (ordered.last.fetch(:distance) - ordered.first.fetch(:distance)).round(1),
          occurrences: ordered.length,
          climb_summit: ordered.any? { it[:climb_summit] },
          ancestors:
        }
      end

      def passages(occurrences)
        occurrences
          .sort_by { it.fetch(:sample_index) }
          .slice_when { |left, right| right.fetch(:sample_index) != left.fetch(:sample_index) + 1 }
          .to_a
      end

      # The provider's feature is the answer unless a settlement of the
      # preferred tier sits both closer to the endpoint than that feature's
      # own centre and within its kind's centre distance: Nominatim can return
      # a way-side dwelling while the recording stops in the village core
      # (PLAN_M1.md §11.1).
      def endpoint_label(result, total_distance:, centers: {}, point: nil)
        return nil unless result.is_a?(Hash)

        entries = places(result)
        feature = symbolize(result[:feature] || result["feature"] || {})
        preferred_kinds, fallback_kinds = endpoint_kinds(total_distance)
        winner = closer_settlement(entries, preferred_kinds, feature, centers, point) ||
          entries.find { preferred_kinds.include?(it[:kind]) } ||
          entries.find { fallback_kinds.include?(it[:kind]) }
        winner ||= feature if feature[:name].present? && ENDPOINT_FALLBACK_KINDS.include?(feature[:kind])
        return nil unless winner

        label = winner.slice(:name, :kind)
        distance = winner[:center_distance] || center_distance(winner, centers, point)
        label[:center_distance] = distance.round(1) if distance
        label
      end

      def endpoint_kinds(total_distance)
        if total_distance.to_f <= ENDPOINT_LOCAL_MAX_DISTANCE
          [ ENDPOINT_FALLBACK_KINDS, ENDPOINT_BROAD_KINDS ]
        else
          [ ENDPOINT_BROAD_KINDS, ENDPOINT_FALLBACK_KINDS ]
        end
      end

      def closer_settlement(entries, preferred_kinds, feature, centers, point)
        latitude, longitude = coordinates(point)
        feature_center = center_of(feature, centers)
        return nil unless latitude && longitude && feature_center

        reference = Distance.metres(latitude, longitude, feature_center.fetch(:latitude), feature_center.fetch(:longitude))
        candidates = entries.filter_map do |entry|
          next unless preferred_kinds.include?(entry[:kind])

          center = center_of(entry, centers)
          next unless center

          distance = Distance.metres(latitude, longitude, center.fetch(:latitude), center.fetch(:longitude))
          limit = Settlements::CENTER_DISTANCE_LIMIT[entry[:kind].to_s]
          next unless limit && distance <= limit && distance < reference

          entry.merge(center_distance: distance.round(1))
        end
        candidates.min_by { |entry| [ entry.fetch(:center_distance), entry[:name].to_s ] }
      end

      def center_distance(entry, centers, point)
        latitude, longitude = coordinates(point)
        center = center_of(entry, centers)
        return nil unless latitude && longitude && center

        Distance.metres(latitude, longitude, center.fetch(:latitude), center.fetch(:longitude))
      end

      def center_of(entry, centers)
        latitude = entry[:center_latitude] || entry["center_latitude"]
        longitude = entry[:center_longitude] || entry["center_longitude"]
        return { latitude:, longitude: } if latitude.is_a?(Numeric) && longitude.is_a?(Numeric)

        centers[[ normalize(entry[:name]), entry[:kind].to_s ]]
      end

      def center_index(centers)
        Array(centers).each_with_object({}) do |center, index|
          value = center.respond_to?(:to_h) ? center.to_h : {}
          name = (value[:name] || value["name"]).to_s
          kind = (value[:kind] || value["kind"]).to_s
          latitude = value[:latitude] || value["latitude"]
          longitude = value[:longitude] || value["longitude"]
          next unless name.strip.present? && kind.present? && latitude.is_a?(Numeric) && longitude.is_a?(Numeric)

          index[[ normalize(name), kind ]] ||= { latitude:, longitude: }
        end
      end

      def coordinates(point)
        return [ nil, nil ] unless point.respond_to?(:to_h)

        value = point.to_h
        latitude = value[:latitude] || value["latitude"]
        longitude = value[:longitude] || value["longitude"]
        latitude.is_a?(Numeric) && longitude.is_a?(Numeric) ? [ latitude, longitude ] : [ nil, nil ]
      end

      def symbolize(value)
        value.to_h.symbolize_keys
      end

      def normalize(name)
        I18n.transliterate(name.to_s).downcase.strip
      end
    end
  end
end
