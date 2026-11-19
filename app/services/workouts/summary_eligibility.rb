# frozen_string_literal: true

module Workouts
  # Whether a workout may be summarised by the assistant (docs/dev/AI.md): the
  # instance offers the feature, the owner consented and is active, and the
  # workout is a recording whose analysis ran. A refusal writes no row: the
  # card is not rendered and nothing is queued.
  #
  # A positionless recording and a virtual workout stay eligible — the summary
  # reads metrics and formatted facts, never a coordinate.
  module SummaryEligibility
    module_function

    def reason(workout)
      return :disabled unless Allure::Assistant::Config.enabled?
      return :not_consented unless workout.user.ai_enabled?
      return :deactivated if workout.user.deactivated?
      return :not_recording unless workout.recording?
      return :analysis_missing unless workout.analysis_version.positive?

      nil
    end

    def eligible?(workout) = reason(workout).nil?

    # The sweep's scope: every recording whose owner consented.
    def scope
      Workout.recordings
             .joins(:user)
             .where(users: { ai_enabled: true, suspended_at: nil, deletion_scheduled_at: nil })
             .where("workouts.analysis_version > 0")
    end
  end
end
