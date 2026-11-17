# frozen_string_literal: true

module Federation
  module Outbox
    # The owner takes back an invitation sent to a remote account
    # (docs/dev/SHARED-ACTIVITIES.md): an `Undo` of the Invite, sent exactly where the
    # Invite was attempted; deliveries never attempted are cancelled instead,
    # so an invitation that never left stays unsent. Like the comment relay's
    # withdrawal, it rides on the Invite's publication.
    class ParticipationUndoInvite
      def initialize(participation:)
        @participation = participation
      end

      def call!
        invite = FederationOutboxEvent.find_by(activity_uri: @participation.wire_activity_uri)
        return unless invite

        # An Invite not expanded yet has no delivery to cancel: the event
        # itself stops, so it can never go out later.
        invite.update!(status: "cancelled") if invite.status.in?(%w[preparing pending])
        recipients = Workouts::PublicationWithdrawal.recipient_uris_for(invite)
        Workouts::PublicationWithdrawal.cancel_unattempted!(invite)
        return if recipients.empty?

        owner = invite.actor
        EventBuilder.new(
          actor: owner,
          subject_type: invite.subject_type,
          subject_id: invite.subject_id,
          workout_publication_id: invite.workout_publication_id,
          activity_type: "Undo",
          object_uri: owner.uri,
          idempotency_key: "participation:undo-invite:#{@participation.uuid}",
          payload: {
            "type" => "Undo",
            "actor" => owner.uri,
            "object" => { "type" => "Invite", "id" => invite.activity_uri, "object" => invite.payload["object"] },
            "to" => recipients,
            "cc" => []
          },
          audience: { "recipients" => recipients, "to" => recipients, "cc" => [] }
        ).call!
      end
    end
  end
end
