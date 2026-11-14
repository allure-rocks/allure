# frozen_string_literal: true

module Workouts
  # Whether every enrichment an import starts has settled
  # (PLAN_AUTO_PUBLISHING.md §4). Each check reads the derivation's own marker
  # (PLAN_DERIVATIONS.md), so it costs no extra bookkeeping:
  #
  # - elevation: no terrain-elevation request pending (the importer records
  #   one when it enqueues the enrichment; applying or giving up clears it);
  # - segments: the matching job stamped the current loop generation (a
  #   reanalysis resets it, so a terrain profile is matched again);
  # - places: the toponymy reached a terminal state (virtual sports have none);
  # - route_image: the owner image is of the current renderer generation;
  # - weather: the weather reached a terminal state, waited for only when a
  #   waiting automatic publication's profile shares it (PLAN_WEATHER.md §5).
  #
  # - photos: no photo of the workout is still being processed, so an
  #   automatic publication takes every photo uploaded in time
  #   (PLAN_PHOTOS.md §5.3).
  #
  # A failed enrichment counts as settled: it will not improve by waiting.
  class AutoPublicationReadiness
    CHECKS = %i[elevation segments places route_image weather photos].freeze

    def initialize(workout)
      @workout = workout
    end

    def pending
      CHECKS.reject { |check| settled?(check) }
    end

    def ready? = pending.empty?

    private

    def settled?(check)
      case check
      when :elevation then @workout.elevation_source_requested.blank?
      when :segments then @workout.loop_reuse_version >= Segments::LoopReuse::VERSION
      when :places then places_settled?
      when :route_image then @workout.route_image_version >= RouteImage::VERSION
      when :weather then weather_settled?
      when :photos then !@workout.photos.processing.exists?
      end
    end

    def weather_settled?
      return true unless weather_shared?
      return true unless WeatherEligibility.eligible?(@workout)

      @workout.weather.present? && @workout.weather.settled?
    end

    def weather_shared?
      @workout.auto_publications.waiting.includes(:publishing_profile).any? do |row|
        PublishingProfile.setting_enabled?(row.publishing_profile&.settings, "weather")
      end
    end

    def places_settled?
      return true if @workout.sport.virtual?

      toponymy = @workout.toponymy
      toponymy.present? && !toponymy.pending?
    end
  end
end
