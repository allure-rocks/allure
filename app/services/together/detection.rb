# frozen_string_literal: true

module Together
  # Compares a recording with its candidates and suggests a link for each
  # match (PLAN_TOGETHER.md §8). A suggestion is a pending `detection` link
  # that both accounts must confirm; both learn of it at once through the
  # same `participation_suggested` notice, which names the counterpart and
  # nothing else. A pair already known to a participation, in any state and
  # either orientation, is never suggested again: a refusal or a withdrawal
  # stays the last word, and a credit between them is the credit-to-link
  # suggestion's business.
  class Detection
    def self.call(workout) = new(workout).call

    def initialize(workout)
      @workout = workout
    end

    def call
      # Co-presence compares tracks; a positionless recording has none
      # (PLAN_NO_GPS.md §6).
      return [] unless @workout.recording? && @workout.positioned?

      CreditLinkSuggestion.for_recording(@workout)
      own = nil
      suggested = CandidateQuery.for_workout(@workout).filter_map do |other|
        next if known_pair?(@workout, other)

        own ||= Recordings.for(@workout)
        next unless Allure::Together::Detector.call(own, Recordings.for(other)).match?

        suggest(@workout, other)
      end
      # The generation marker the history backfill counts (§8, slice 3d).
      @workout.update_columns(together_detection_version: Allure::Together::Detector::VERSION)
      suggested
    end

    private

    def known_pair?(first, second)
      actors = [ first.user.actor&.id, second.user.actor&.id ].compact
      WorkoutParticipation
        .where(workout_id: [ first.id, second.id ], participant_actor_id: actors)
        .or(WorkoutParticipation.where(workout_id: [ first.id, second.id ], participant_workout_id: [ first.id, second.id ]))
        .exists?
    end

    # The earlier import is the source; the orientation carries no meaning,
    # so the other one is used when the earlier's partner recording is
    # already linked elsewhere (one recording links to one source).
    def suggest(first, second)
      source, recording = orientation(first, second)
      return unless source

      participation = source.workout_participations.create!(
        participant_actor: recording.user.actor,
        participant_workout: recording,
        kind: "link",
        origin: "detection",
        detector_version: Allure::Together::Detector::VERSION
      )
      notify(participation)
      participation
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      nil
    end

    def orientation(first, second)
      ordered = [ first, second ].sort_by { |workout| [ workout.created_at, workout.id ] }
      [ ordered, ordered.reverse ].find do |source, recording|
        recording.user.actor && !WorkoutParticipation.live.exists?(participant_workout_id: recording.id)
      end
    end

    def notify(participation)
      source_owner = participation.workout.user
      counterpart = participation.participant_user
      Notifications::Create.new(user: source_owner, kind: "participation_suggested",
                                actor: participation.participant_actor, subject: participation).call!
      Notifications::Create.new(user: counterpart, kind: "participation_suggested",
                                actor: source_owner.actor, subject: participation).call!
    end
  end
end
