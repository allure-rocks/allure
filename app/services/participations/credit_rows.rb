# frozen_string_literal: true

module Participations
  # Gives a confirmed credit its credit row (docs/dev/SHARED-ACTIVITIES.md): the
  # attached row when it exists, else a detached row of the same owner the
  # participant kept from a deleted source of the same outing (the owner
  # re-imported it), else a new one. Idempotent per source and participant;
  # the source's row lock serializes concurrent runs.
  class CreditRows
    # A re-imported activity starts where the deleted one did.
    REATTACH_WINDOW = 120.seconds

    def self.attach(participation) = new(participation).attach

    def initialize(participation)
      @participation = participation
    end

    def attach
      return unless @participation.confirmed? && @participation.kind == "credit"

      participant = @participation.participant_user
      return unless participant

      source = @participation.workout
      created = false
      row = Workout.transaction do
        source.lock!
        owner_actor = source.user.actor || Federation::ActorProvisioner.new(user: source.user).call!
        credit = source.credit_rows.find_by(user: participant) ||
                 reattachable(source, participant, owner_actor) ||
                 participant.workouts.build(origin: "credit")
        credit.assign_attributes(credited_from: source, credited_by: owner_actor, credit_detached_at: nil)
        credit.assign_attributes(CreditSync.attributes_from(source))
        created = credit.new_record?
        credit.save!
        credit
      end
      # A new credit row reaches the participant's integrations like an import;
      # a re-attached one is the same workout (docs/dev/SHARED-ACTIVITIES.md).
      Webhooks::Events.workout_created(row) if created
      CreditSync.new(row).derive
    end

    private

    def reattachable(source, participant, owner_actor)
      participant.workouts.credit_rows_only
        .where(credited_from_workout_id: nil, credited_by_actor_id: owner_actor.id, sport_id: source.sport_id)
        .where(started_at: (source.started_at - REATTACH_WINDOW)..(source.started_at + REATTACH_WINDOW))
        .ordered_by_start_proximity_to(source.started_at)
        .first
    end
  end
end
