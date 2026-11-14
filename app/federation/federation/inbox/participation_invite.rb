# frozen_string_literal: true

module Federation
  module Inbox
    # Receives a remote owner's invitation to confirm taking part in a
    # publication (PLAN_TOGETHER.md §7). It is addressed to one local account,
    # which must hold the publication — an active received note by that owner
    # and an active entitlement, never a public note read by chance — and
    # still follow its owner, and it
    # carries only the sport slug and the start; the figures stay on the note.
    # Idempotent by the Invite's identity; a refused publication is never
    # offered again, and a pending one is kept rather than duplicated.
    class ParticipationInvite
      SPORT_SLUG = /\A[a-z][a-z0-9_]{0,63}\z/

      # The Invite overtook the publication's Create, which the inbox
      # processes asynchronously: the item retries instead of losing it.
      class NoteNotYetReceived < StandardError; end

      def initialize(item:, activity:, now: Time.current)
        @item = item
        @activity = activity
        @now = now
      end

      def call!
        raise Rejected, "activity actor does not match the sender" unless @activity["actor"] == @item.actor_uri
        raise Rejected, "the invitation names another account" unless @activity["target"] == recipient.uri
        raise Rejected, "the invited account is not local" unless recipient.local? && recipient.user

        existing = RemoteParticipation.find_by(invite_activity_uri: @item.activity_uri)
        return existing if existing

        note = held_note!
        live = RemoteParticipation.live.find_by(recipient_actor: recipient, object_uri: note.object_uri)
        # A new Invite for a pending one — the owner withdrew and invited
        # again — takes it over, so a late Undo of the old Invite misses it.
        live.update!(invite_activity_uri: @item.activity_uri) if live&.pending?
        return live if live

        participation = RemoteParticipation.create!(
          remote_note: note,
          recipient_actor: recipient,
          object_uri: note.object_uri,
          invite_activity_uri: @item.activity_uri,
          sport_slug: facts["sport_slug"],
          started_at: facts["started_at"]
        )
        notify(participation, note)
        participation
      end

      private

      def recipient = @item.recipient_actor

      def held_note!
        object = @activity["object"]
        uri = object.is_a?(Hash) ? object["id"] : object
        note = RemoteNote.find_by(object_uri: uri.to_s)
        raise NoteNotYetReceived, "the publication has not arrived yet" if note.nil? && follows_sender?
        raise Rejected, "the invitation names an unknown publication" unless note&.active?
        raise Rejected, "only the publication's author invites" unless note.actor.uri == @item.actor_uri
        raise Rejected, "the invited account does not hold the publication" unless note.entitled_to?(recipient)
        raise Rejected, "the invited account does not follow the author" unless follows_sender?

        note
      end

      def follows_sender?
        Following.accepted.joins(:followed_actor)
          .exists?(follower_actor: recipient, actors: { uri: @item.actor_uri })
      end

      # Bounded: a sport slug the catalogue may know and a parseable instant;
      # anything else is dropped, never trusted.
      def facts
        @facts ||= begin
          raw = @activity["_allure_participation"]
          raw = {} unless raw.is_a?(Hash)
          slug = raw["sport_slug"].to_s
          {
            "sport_slug" => (slug if SPORT_SLUG.match?(slug)),
            "started_at" => parse_time(raw["started_at"])
          }
        end
      end

      def parse_time(value)
        Time.iso8601(value.to_s)
      rescue ArgumentError
        nil
      end

      def notify(participation, note)
        Notifications::Create.new(
          user: recipient.user,
          kind: "participation_requested",
          actor: note.actor,
          subject: participation
        ).call!
      end
    end
  end
end
