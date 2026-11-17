# frozen_string_literal: true

module Workouts
  # The anomaly kinds that are this device's ordinary behaviour for one
  # account (docs/dev/WORKOUT.md): a kind found in most of the owner's analysed
  # workouts from the same recording device. Such findings are explained once
  # instead of flagged; a finding that changes a figure is never one of them.
  class AnomalySignatures
    MINIMUM_WORKOUTS = 5
    SHARE = 0.7

    def initialize(workout:)
      @workout = workout
    end

    def kinds
      return [] if @workout.source.blank?

      scope = @workout.user.workouts.where(source: @workout.source)
                      .where(analysis_version: Allure::Gpx::Analyzer::VERSION..)
      total = scope.count
      return [] if total < MINIMUM_WORKOUTS

      scope.from("workouts, jsonb_object_keys(workouts.data_anomalies -> 'counts') AS kind")
           .group("kind").count("DISTINCT workouts.id")
           .select { |_kind, count| count >= SHARE * total }
           .keys
    end
  end
end
