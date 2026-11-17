# frozen_string_literal: true

module Segments
  # Names the place a course runs through, for the segment index
  # (docs/dev/SEGMENTS.md): one Nominatim reverse lookup at the course
  # midpoint, half-way along its length, stored on the segment. The geometry
  # never changes, so a course is geocoded once. A virtual course has no real
  # place, and an instance without a provider leaves the course pending for a
  # later sweep. The place stays local: it never enters a publication.
  class PlaceGeocoder
    # The feature kinds that name a place a reader recognizes; a road or an
    # isolated building falls back to the settlement around it.
    FEATURE_KINDS = %w[
      summit pass hut viewpoint landmark waterfall spring cave
      locality neighbourhood suburb hamlet village town city municipality
    ].freeze
    SETTLEMENT_KINDS = %w[village town city municipality hamlet suburb locality neighbourhood].freeze

    def initialize(segment:, client: :default, clock: -> { Time.current })
      @segment = segment
      @client = client == :default ? default_client : client
      @clock = clock
    end

    # Raises Allure::Toponyms::Nominatim::UnavailableError on a provider or
    # transport failure, so the job can retry.
    def call(force: false)
      return @segment if !force && %w[ready unavailable].include?(@segment.place_status)
      return mark("unavailable", nil) if @segment.sport&.virtual?
      return @segment unless @client

      longitude, latitude = midpoint
      return mark("unavailable", nil) if longitude.nil? || latitude.nil?

      name = place_name(@client.reverse(longitude:, latitude:, zoom: Allure::Toponyms::Nominatim::MARKER_ZOOM))
      name ? mark("ready", name) : mark("unavailable", nil)
    end

    private

    def mark(status, name)
      @segment.update_columns(place_status: status, place_name: name, place_geocoded_at: @clock.call)
      @segment
    end

    def midpoint
      Segment.where(id: @segment.id).pick(
        Arel.sql("ST_X(ST_LineInterpolatePoint(segments.geom::geometry, 0.5))"),
        Arel.sql("ST_Y(ST_LineInterpolatePoint(segments.geom::geometry, 0.5))")
      )
    end

    def place_name(result)
      return nil unless result.is_a?(Hash)

      feature = result[:feature]
      name = feature[:name] if feature.is_a?(Hash) && FEATURE_KINDS.include?(feature[:kind].to_s)
      name ||= Array(result[:hierarchy]).find { SETTLEMENT_KINDS.include?(it[:kind].to_s) }&.dig(:name)
      name ||= Array(result[:hierarchy]).first&.dig(:name)
      name.to_s.strip.truncate(120).presence
    end

    def default_client
      base_url = Allure::Toponyms::Config.base_url
      Allure::Toponyms::Nominatim.new(base_url:) if base_url
    end
  end
end
