# frozen_string_literal: true

module Workouts
  # Owner-scoped derived-data maintenance behind the settings Data page
  # (docs/dev/DERIVATIONS.md). One cursor sweep per kind, limited to the
  # account's own workouts and courses, batched so a single account cannot
  # flood the queues, and throttled to one running sweep per (account, kind).
  #
  # Kinds:
  # - `rebuild`: workouts whose analysis or import-detection generation is
  #   older than the current one (Workouts::RebuildJob);
  # - `route_images`: owner workout images that are missing or stale
  #   (Workouts::RenderRouteImageJob);
  # - `segment_images`: owner segment, route and loop images that are missing
  #   or stale (Segments::RenderRouteImageJob);
  # - `places`: the displayed place list is stale, or the stored toponymy is
  #   missing/pending/failed or built by an older algorithm and can be geocoded
  #   again (the geocoding job is globally paced, so this only schedules work);
  # - `elevation`: elevation-less workouts of an opted-in account on an
  #   instance with a terrain provider (Workouts::ApplyElevationSourceJob);
  # - `weather`: positioned workouts of a consenting account without weather
  #   or with an older weather generation (PLAN_WEATHER.md §5; the weather job
  #   is paced, so this only schedules work);
  # - `loops`: positioned recordings with an older detection/reuse generation,
  #   even without a loop yet (Segments::MatchWorkoutJob);
  # - `heart_rate`: recordings whose heart-rate histogram is missing or older
  #   than the current version (PLAN_HEART_RATE.md §3.4), rebuilt inline from
  #   the stored points;
  # - `route_suggestions`: recordings the recurring-route detector has not
  #   examined yet (PLAN_SEGMENTS.md §7.7); the account sweep walks them newest
  #   first, so this kind enqueues it once instead of dispatching per record.
  #
  # A user sweep never bypasses a contract: it only rebuilds to the state the
  # current code and catalogue already define.
  class UserBackfillJob < ApplicationJob
    BATCH_SIZE = 25
    KINDS = %w[rebuild route_images segment_images places elevation weather loops heart_rate route_suggestions].freeze

    queue_as :default
    limits_concurrency key: ->(user_id, kind, **) { "user-backfill-#{user_id}-#{kind}" }, duration: 30.minutes

    retry_on ActiveRecord::Deadlocked, ActiveRecord::ConnectionNotEstablished,
             ActiveRecord::SerializationFailure, wait: :polynomially_longer, attempts: 5
    discard_on ActiveJob::DeserializationError

    class << self
      def pending_scope(user, kind)
        case kind.to_s
        when "rebuild" then rebuild_scope(user)
        when "route_images" then route_image_scope(user)
        when "segment_images" then segment_image_scope(user)
        when "places" then places_scope(user)
        when "elevation" then elevation_scope(user)
        when "weather" then weather_scope(user)
        when "loops" then loop_scope(user)
        when "heart_rate" then HeartRates::BackfillJob.pending_scope.where(user_id: user.id)
        when "route_suggestions" then Segments::RouteSuggestionSweepJob.pending_scope.where(user_id: user.id)
        else raise ArgumentError, "unknown user backfill kind: #{kind.inspect}"
        end
      end

      def counts(user)
        KINDS.index_with { |kind| pending_scope(user, kind).count }
      end

      private

      # Only workouts that still keep their original file can be reconciled
      # (docs/dev/DERIVATIONS.md); a fileless workout is never counted.
      def rebuild_scope(user)
        user.workouts
          .joins(:original_file_attachment)
          .where(
            "analysis_version < :analysis OR import_detection_version < :detection",
            analysis: Allure::Gpx::Analyzer::VERSION,
            detection: ImportDetection::VERSION
          )
      end

      # Credit rows have no track: no image, no geocoding (docs/dev/SHARED-ACTIVITIES.md).
      def route_image_scope(user)
        user.workouts.recordings.where(route_image_version: ...RouteImage::VERSION)
      end

      def segment_image_scope(user)
        user.segments.where(route_image_version: ...Segments::RouteImage::VERSION)
      end

      # Two independent repairs: the place list assembly is stale, or the
      # geocoding itself is missing/failed. A virtual workout is never
      # geocoded and is left to its venue catalog.
      def places_scope(user)
        assembly = BackfillPlacesJob.pending_scope.where(workouts: { user_id: user.id }).select(:id)
        geocoding = geocoding_scope(user).select(:id)

        user.workouts.where(id: assembly).or(user.workouts.where(id: geocoding))
      end

      def geocoding_scope(user)
        user.workouts.recordings
          .joins(:sport)
          .where(sports: { virtual: false })
          .left_joins(:toponymy)
          .where(
            "workout_toponymies.id IS NULL OR workout_toponymies.status IN ('pending', 'failed') " \
            "OR workout_toponymies.algorithm_version < ?",
            ToponymyEnricher::ALGORITHM_VERSION
          )
      end

      def elevation_scope(user)
        return user.workouts.none unless Allure::Elevation::Config.configured?

        BackfillElevationJob.pending_scope.where(workouts: { user_id: user.id })
      end

      def weather_scope(user)
        BackfillWeatherJob.pending_scope.where(workouts: { user_id: user.id })
      end

      def loop_scope(user)
        Segments::BackfillLoopReuseJob.pending_scope.where(workouts: { user_id: user.id })
      end
    end

    def perform(user_id, kind, after_id: 0)
      user = User.find_by(id: user_id)
      kind = kind.to_s
      return if user.nil? || !KINDS.include?(kind)

      # The route-suggestion sweep has its own newest-first walk; dispatching
      # per record here would process the account oldest first.
      if kind == "route_suggestions"
        Segments::RouteSuggestionSweepJob.perform_later(user.id)
        return
      end

      scope = self.class.pending_scope(user, kind)
      records = scope
        .where("#{scope.table_name}.id > ?", after_id)
        .order(:id)
        .limit(BATCH_SIZE)
        .to_a

      records.each { |record| dispatch(kind, record) }

      self.class.perform_later(user_id, kind, after_id: records.last.id) if records.length == BATCH_SIZE
    end

    private

    def dispatch(kind, record)
      case kind
      when "rebuild" then RebuildJob.perform_later(record)
      when "route_images" then RenderRouteImageJob.perform_later(record)
      when "segment_images" then Segments::RenderRouteImageJob.perform_later(record)
      when "places" then dispatch_places(record)
      when "elevation" then ApplyElevationSourceJob.perform_later(record, "dem")
      when "weather" then WeatherRefresh.new(workout: record).call
      when "loops" then Segments::MatchWorkoutJob.perform_later(record)
      when "heart_rate" then HeartRates::Rebuild.new(workout: record).call
      end
    end

    def dispatch_places(workout)
      toponymy = workout.toponymy
      if toponymy && (toponymy.ready? || toponymy.partial?) &&
          toponymy.algorithm_version >= ToponymyEnricher::ALGORITHM_VERSION
        RebuildPlacesJob.perform_later(workout)
      else
        ToponymyRefresh.new(workout:).call
      end
    end
  end
end
