# frozen_string_literal: true

module Participations
  # The recordings a participant may name to turn a participation into a link
  # (docs/dev/SHARED-ACTIVITIES.md): their own, not the source itself, and not
  # already linked to another live participation (the live-recording partial
  # unique index would otherwise raise). Shared by `Decide` and `Convert`.
  module RecordingRules
    # The picker offers recordings starting this close to the source, closest
    # first: the same outing, whatever sport each device decided.
    WINDOW = 6.hours
    LIMIT = 10

    module_function

    # The reason a recording cannot be named, or nil when it can.
    def refusal(participation:, user:, recording:)
      return "not the participant's workout" unless recording.user_id == user.id
      return "only a recording can be linked" unless recording.recording?
      return "the recording cannot be the source workout" if recording.id == participation.workout_id
      return "the recording is already linked" if linked_elsewhere?(participation, recording)

      nil
    end

    def candidates(participation:, user:)
      source = participation.workout
      user.workouts.recordings
        .where(started_at: (source.started_at - WINDOW)..(source.started_at + WINDOW))
        .where.not(id: source.id)
        .where.not(id: WorkoutParticipation.live.where.not(participant_workout_id: nil).select(:participant_workout_id))
        .includes(:sport)
        .ordered_by_start_proximity_to(source.started_at)
        .limit(LIMIT)
    end

    def linked_elsewhere?(participation, recording)
      WorkoutParticipation.live
        .where(participant_workout_id: recording.id)
        .where.not(id: participation.id)
        .exists?
    end
  end
end
