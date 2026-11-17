# frozen_string_literal: true

module Participations
  # Gives a confirmed invitation from another instance its credit row
  # (docs/dev/SHARED-ACTIVITIES.md): a metrics-only workout of the local account,
  # counting in its statistics and column records like a local credit, built
  # from the received note's figures — which the owner's instance required
  # the publication to share — and the sport slug and start the Invite
  # carried. It has no track, so no best effort, segment effort or climb.
  # A detached credit of the same owner for the same outing (its note was
  # deleted, then republished and the account invited again) is re-attached
  # instead of counting the outing twice. Idempotent per participation.
  module RemoteCreditRows
    REATTACH_WINDOW = CreditRows::REATTACH_WINDOW

    module_function

    def attach(participation)
      return unless participation.confirmed?

      user = participation.recipient_user
      note = participation.remote_note
      attributes = attributes_for(participation, note)
      return unless user && note&.active? && attributes

      created = false
      row = Workout.transaction do
        credit = participation.credit_row ||
                 reattachable(user, note, attributes) ||
                 user.workouts.build(origin: "credit")
        credit.assign_attributes(attributes.merge(remote_participation: participation, credited_by: note.actor,
                                                  credit_detached_at: nil))
        created = credit.new_record?
        credit.save!
        credit
      end
      Webhooks::Events.workout_created(row) if created
      row
    end

    # Nil when a figure the credit needs is missing: the owner's instance
    # requires them, so only a peer breaking that contract lands here.
    def attributes_for(participation, note)
      metrics = note.metrics.to_h
      required = Propose::REMOTE_REQUIRED_METRICS.to_h { |key| [ key, metrics[key] ] }
      return if required.values.any?(&:nil?)

      sport = Sport.find_by(slug: participation.sport_slug) || Federation::RemoteNoteView.new(note).sport
      started_at = participation.started_at || note.started_at
      return unless sport.is_a?(Sport) && sport.persisted? && started_at

      duration = required["duration"].to_i
      moving_time = [ required["moving_time"].to_i, duration ].min
      {
        sport:, started_at:, title: note.title,
        distance: required["distance"], ascent: required["ascent"], descent: required["descent"],
        average_speed: required["average_speed"], duration:, moving_time:, pause_time: duration - moving_time,
        average_pace: metrics["average_pace"]&.to_i, best_pace: metrics["best_pace"]&.to_i,
        max_speed: metrics["max_speed"]
      }
    end

    def reattachable(user, note, attributes)
      user.workouts.credit_rows_only
        .where(credited_by_actor_id: note.actor_id, sport_id: attributes[:sport].id)
        .where.not(credit_detached_at: nil)
        .where(started_at: (attributes[:started_at] - REATTACH_WINDOW)..(attributes[:started_at] + REATTACH_WINDOW))
        .order(:started_at, :id)
        .first
    end
  end
end
