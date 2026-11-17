# frozen_string_literal: true

module Workouts
  # Whether a workout may be sent to the weather provider
  # (docs/dev/WEATHER.md): the instance offers the feature, the owner consented and is active,
  # and the workout is a positioned recording of a real-world sport. A manual
  # entry, a credit row, a positionless recording and a virtual sport never
  # have weather.
  module WeatherEligibility
    # Reasons that make any stored weather meaningless, so it is discarded.
    STRUCTURAL = %i[not_recording positionless virtual].freeze

    module_function

    def reason(workout)
      return :disabled unless Allure::Weather::Config.enabled?
      return :not_consented unless workout.user.weather_enrichment_enabled?
      return :deactivated if workout.user.deactivated?
      return :not_recording unless workout.recording?
      return :positionless unless workout.positioned?
      return :virtual if workout.sport.virtual?

      nil
    end

    def eligible?(workout) = reason(workout).nil?

    def scope
      Workout.positioned
        .joins(:sport, :user)
        .where(sports: { virtual: false }, users: { weather_enrichment_enabled: true })
    end
  end
end
