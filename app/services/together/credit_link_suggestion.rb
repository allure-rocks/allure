# frozen_string_literal: true

module Together
  # Finds a credited participant's own recording of the outing they were
  # credited for, and suggests converting the credit into a link
  # (PLAN_TOGETHER.md §8): same time and same place as the credit's source,
  # through the co-presence detector, never a start-time window alone. Until
  # the participant links or dismisses it, the outing counts twice; the
  # suggestion says so. It depends on the participant's own detection switch
  # only: the comparison reads the source server-side and discloses nothing.
  module CreditLinkSuggestion
    # A recording's window is read from its start and duration; the start
    # bound keeps the query on the start-time index.
    MAX_DURATION = CandidateQuery::MAX_DURATION

    module_function

    # A new recording against the sources of its owner's open credits.
    def for_recording(recording)
      actor = participant_actor_for(recording.user)
      return [] unless recording.recording? && actor

      start = recording.started_at
      finish = start + recording.duration
      open_credits.where(participant_actor: actor)
        .joins(:workout)
        .where(workouts: { started_at: (start - MAX_DURATION)..finish })
        .merge(Workout.ending_at_or_after(start))
        .includes(workout: :sport)
        .filter_map { |participation| suggest(participation, recording) }
    end

    # A newly confirmed credit against the participant's existing recordings.
    def for_participation(participation)
      user = participation.participant_user
      return unless user && participant_actor_for(user) && open_credits.exists?(participation.id)

      source = participation.workout
      start = source.started_at
      finish = start + source.duration
      user.workouts.recordings
        .where(started_at: (start - MAX_DURATION)..finish)
        .ending_at_or_after(start)
        .includes(:sport)
        .order(:started_at, :id)
        .each do |recording|
          suggested = suggest(participation, recording)
          return suggested if suggested
        end
      nil
    end

    def open_credits
      WorkoutParticipation.confirmed.credits.where(suggested_workout_id: nil, link_suggestion_dismissed_at: nil)
    end

    def participant_actor_for(user)
      user.actor if user.together_detection_enabled && !user.deactivated?
    end

    def suggest(participation, recording)
      return if WorkoutParticipation.live.exists?(participant_workout_id: recording.id)
      return unless Allure::Together::Detector.call(Recordings.for(participation.workout), Recordings.for(recording)).match?

      participation.update!(suggested_workout: recording)
      Notifications::Create.new(user: recording.user, kind: "participation_link_suggested", subject: participation).call!
      participation
    end
  end
end
