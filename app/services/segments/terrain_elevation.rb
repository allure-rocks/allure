# frozen_string_literal: true

module Segments
  # Replaces a course's frozen elevation figures with the terrain service's
  # (PLAN_ELEVATION.md §10). Every course then reads one reference profile,
  # whatever device recorded it. A public course is already visible to every
  # member, so the instance's service alone suffices; a private or
  # followers-only one also needs its owner's terrain consent. A provider that
  # does not answer the whole course leaves the device figures in place.
  class TerrainElevation
    class ProviderNotConfiguredError < StandardError; end

    def self.eligible?(segment, config: Allure::Elevation::Config)
      return false unless config.configured?
      return false unless segment.elevation_source == "device" && segment.geom.present?
      return false if segment.user.nil? || segment.user.deactivated?
      return false if segment.sport && (!segment.sport.records_elevation || segment.sport.virtual)

      segment.visibility == "public" || segment.user.elevation_enrichment_enabled?
    end

    # The relation mirror of `eligible?`, for the backfill and its count: a
    # course never tried, or whose last try failed.
    def self.pending_scope
      eligible = Segment
        .where(elevation_source: "device", elevation_status: [ nil, "failed" ])
        .joins(:user).left_joins(:sport)
        .where(users: { suspended_at: nil, deletion_scheduled_at: nil })
      by_visibility = eligible
        .where(visibility: "public")
        .or(eligible.where(users: { elevation_enrichment_enabled: true }))
      by_visibility
        .where(sports: { id: nil })
        .or(by_visibility.where(sports: { records_elevation: true, virtual: false }))
    end

    def initialize(segment:, config: Allure::Elevation::Config, client: nil, sleeper: nil)
      @segment = segment
      @config = config
      @client = client || config.client
      @sleeper = sleeper || ->(seconds) { sleep(seconds) }
    end

    def call
      raise ProviderNotConfiguredError, "no elevation provider configured" unless @config.configured?
      return unless self.class.eligible?(@segment, config: @config)

      samples = Allure::Elevation::CourseTerrain.samples(
        @segment.geom.points.map { |point| [ point.x, point.y ] },
        interval_metres: @config.sample_metres,
        max_requests: @config.max_requests_per_workout
      )
      result = Allure::Elevation::CourseTerrain.metrics(samples, fetch(samples), distance: @segment.distance)
      return @segment.update_columns(elevation_status: "unavailable", updated_at: Time.current) unless result

      @segment.update_columns(
        elevation_source: "dem",
        elevation_status: "ready",
        ascent: result.ascent,
        descent: result.descent,
        min_elevation: result.min_elevation,
        max_elevation: result.max_elevation,
        average_grade: result.average_grade&.round(2),
        elevation_profile: result.profile,
        updated_at: Time.current
      )
    end

    private

    def fetch(samples)
      interval_seconds = 1.0 / @config.requests_per_second
      Allure::Elevation::Sampler.chunks(samples).each_with_index.flat_map do |chunk, index|
        @sleeper.call(interval_seconds) if index.positive?
        @client.elevations(chunk.map { |sample| [ sample.latitude, sample.longitude ] })
      end
    end
  end
end
