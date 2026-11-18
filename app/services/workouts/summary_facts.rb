# frozen_string_literal: true

module Workouts
  # The facts of one workout and their digest (docs/dev/AI.md §3.1): the
  # owner-only context, the recorded heart-rate series for the cardiac drift,
  # and the member's language and units. Pure apart from reading the track.
  class SummaryFacts
    SERIES_POINTS = 600
    Snapshot = Data.define(:facts, :digest, :locale, :unit_system)

    def initialize(workout)
      @workout = workout
    end

    def call
      locale = workout.user.locale
      unit_system = workout.user.unit_system
      context = ContextPayload.new(workout, user: workout.user).call
      context[:series] = heart_rate_series
      facts = Allure::Insights::Facts.build(context, locale:)
      digest = Allure::Insights::Facts.digest(facts, version: Allure::Insights::VERSION,
                                              locale:, unit_system:)
      Snapshot.new(facts:, digest:, locale:, unit_system:)
    end

    private

    attr_reader :workout

    def heart_rate_series
      return [] unless workout.heart_rate

      points = Allure::Gpx::ChartSeries.new(
        workout_started_at: workout.started_at,
        segments: workout.track_segments.to_a,
        max_points: SERIES_POINTS,
        series: %i[heart_rate]
      ).call
      points.filter_map do |point|
        { elapsed_time: point[:elapsed_time], heart_rate: point[:heart_rate] } if point[:heart_rate]
      end
    end
  end
end
