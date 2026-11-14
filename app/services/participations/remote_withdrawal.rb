# frozen_string_literal: true

module Participations
  # Ends remote participations (PLAN_TOGETHER.md §7.6).
  #
  # On the invited account's instance: its own withdrawal of a confirmation,
  # the owner's `Undo` of the Invite, and the relationship ending — an
  # unfollow, a follow refused, a block. Notices go with the row, and so does
  # an attached credit row, whose destroy hooks recompute the account's
  # records; a credit detached when its note was deleted is kept, as a local
  # one is, for a later invitation to re-attach. When the origin should hear
  # of it, a confirmation taken back yields an `Undo` of the account's
  # `Accept` for the caller to expand after its transaction; a block tells
  # nobody.
  #
  # On the owner's instance, the invitations its peer closes without a word:
  # those riding on a publication that is gone, and those of a participant
  # who stopped following.
  module RemoteWithdrawal
    module_function

    # `destroy_credit: false` is for the credit row's own destroy, which
    # takes it out already.
    def withdraw!(participation, at: Time.current, notify_origin: false, destroy_credit: true)
      return if participation.withdrawn?

      event = nil
      RemoteParticipation.transaction do
        confirmed = participation.confirmed?
        participation.update!(withdrawn_at: at)
        Notifications::Withdraw.new(subject: participation).call!
        credit = participation.reload_credit_row
        credit.destroy! if destroy_credit && credit && credit.credit_detached_at.nil?
        event = Federation::Outbox::ParticipationAnswer.new(participation:).undo_accept! if notify_origin && confirmed
      end
      event
    end

    # The publication is gone (its note or its author deleted): a pending
    # invitation can no longer be answered and closes; a confirmed one stays
    # and its credit row is detached and kept without the owner's title, as
    # for a deleted local source (§6.5), the account told.
    def close_pending!(notes, at: Time.current)
      RemoteParticipation.pending.where(remote_note: notes).find_each { |participation| withdraw!(participation, at:) }
      Workout.credit_rows_only.where(remote_participation: RemoteParticipation.confirmed.where(remote_note: notes))
        .where(credit_detached_at: nil).includes(:user).find_each do |credit|
          credit.update_columns(credit_detached_at: at, title: nil, updated_at: at)
          Notifications::Create.new(user: credit.user, kind: "participation_source_deleted", subject: credit).call!
        end
    end

    # The owner's publication left (withdrawn, replaced, cancelled): the
    # invited instance closes a pending invitation on the note's Delete
    # without answering, so the owner's row closes too. A confirmed one stays.
    def publication_gone!(publication, at: Time.current)
      close_owner_rows!(WorkoutParticipation.active.where(workout_publication_id: publication.id,
                                                          participant_confirmed_at: nil), at:)
    end

    # A remote participant stopped following the owner: its instance ends the
    # invitations without answering a pending one, so the owner's rows end.
    def participant_left!(owner_actor:, participant_actor:, at: Time.current)
      return unless owner_actor.user_id

      close_owner_rows!(WorkoutParticipation.active.where(participant_actor:)
                          .joins(:workout).where(workouts: { user_id: owner_actor.user_id }), at:)
    end

    def close_owner_rows!(scope, at:)
      scope.where.not(wire_activity_uri: nil).find_each do |participation|
        participation.update!(withdrawn_at: at)
        Notifications::Withdraw.new(subject: participation).call!
      end
    end

    # Every pending or confirmed invitation a local account holds from one
    # remote owner; a refusal stays the last word.
    def for_pair!(recipient_actor:, origin_actor:, at: Time.current, notify_origin: false)
      RemoteParticipation.active.joins(:remote_note)
        .where(recipient_actor:, remote_notes: { actor_id: origin_actor.id })
        .filter_map { |participation| withdraw!(participation, at:, notify_origin:) }
    end
  end
end
