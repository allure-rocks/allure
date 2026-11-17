# frozen_string_literal: true

module Federation
  module Outbox
    # The owner invites a remote account to confirm it took part in a
    # published workout (docs/dev/SHARED-ACTIVITIES.md): an ActivityStreams `Invite`
    # whose object is the publication the account already holds and whose
    # target is that account, addressed to it alone. It rides on its
    # publication as a secondary event (docs/dev/COMMENTS.md), so it waits for
    # the publication's Create, passes the publication's rules, and stops with
    # it. It carries no metric and no geometry: the receiver reads the figures
    # from the note it holds, and only the sport slug and the start, which the
    # note does not carry reliably, travel here.
    class ParticipationInvite
      def self.key_for(participation) = "participation:invite:#{participation.uuid}"

      # Deterministic, so the participation remembers it before delivery and
      # the answers that name it resolve.
      def self.activity_uri_for(participation, owner)
        EventBuilder.activity_uri_for(object_uri: owner.uri, activity_type: "Invite", idempotency_key: key_for(participation))
      end

      def initialize(participation:, publication:)
        @participation = participation
        @publication = publication
      end

      def call!
        owner = @publication.actor
        target = @participation.participant_actor
        audience = { "to" => [ target.uri ], "cc" => [] }
        EventBuilder.new(
          actor: owner,
          subject_type: "WorkoutPublication",
          subject_id: @publication.id,
          workout_publication_id: @publication.id,
          activity_type: "Invite",
          object_uri: owner.uri,
          idempotency_key: self.class.key_for(@participation),
          payload: {
            "type" => "Invite",
            "actor" => owner.uri,
            "object" => @publication.object_uri,
            "target" => target.uri,
            # From the publication, not the live workout: the invitation
            # describes what the account holds.
            "_allure_participation" => {
              "sport_slug" => @publication.publication_sport_slug,
              "started_at" => Time.iso8601(@publication.publication_started_at).utc.iso8601
            },
            **audience
          },
          audience:
        ).call!
      end
    end
  end
end
