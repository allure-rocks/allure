# frozen_string_literal: true

module Laps
  # Writes the geocoded label of every detected lap from the workout's stored
  # toponymy. Run by Laps::Rebuild when a toponymy already exists and by
  # Workouts::ToponymyEnricher whenever it lands one, so names always reflect
  # the latest enrichment without a job of their own. A lap with no usable
  # place is cleared rather than left stale.
  class Naming
    def initialize(workout:)
      @workout = workout
    end

    def call
      toponymy = @workout.toponymy
      return if toponymy.nil?

      @workout.detected_laps.to_a.each do |lap|
        name = Allure::Laps::Namer.new(lap:, toponymy:).call
        next if lap.name == name

        lap.update_columns(name:, updated_at: Time.current)
      end
    end
  end
end
