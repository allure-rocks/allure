# frozen_string_literal: true

module HeartRates
  # The highest heart rate the account's recordings hold, as a proposal for
  # its maximum (PLAN_HEART_RATE.md §3.1): the highest bpm a recording spent
  # at least HELD_SECONDS at or above, read from its histogram, so a single
  # plausible-looking spike never sets it. The last 12 months first, the whole
  # history otherwise; never a recording whose maximum the anomaly pass
  # contested, nor one too sparse to tell a second from a minute.
  class ObservedMaximum
    WINDOW = 12.months
    HELD_SECONDS = 10

    Observation = Data.define(:workout, :bpm)

    def initialize(user:, now: Time.current)
      @user = user
      @now = now
    end

    # An Observation, or nil.
    def call
      best(candidates.where(workouts: { started_at: (@now - WINDOW).. })) || best(candidates)
    end

    def self.held_maximum(histogram)
      total = 0
      (histogram.length - 1).downto(0) do |index|
        total += histogram[index]
        return Allure::HeartRate::Histogram.bpm_for(index) if total >= HELD_SECONDS
      end
      nil
    end

    private

    def candidates
      WorkoutHeartRate.joins(:workout).merge(@user.workouts.recordings)
        .where(sparse: false)
        .where.not("'max_heart_rate' = ANY (workouts.contested_metrics)")
    end

    def best(scope)
      id, bpm = scope.pluck(:workout_id, :histogram, "workouts.started_at")
        .filter_map { |workout_id, histogram, started_at| [ workout_id, self.class.held_maximum(histogram), started_at ] }
        .select { |_, held, _| held }
        .max_by { |_, held, started_at| [ held, started_at ] }
      return nil unless id

      Observation.new(workout: @user.workouts.find(id), bpm:)
    end
  end
end
