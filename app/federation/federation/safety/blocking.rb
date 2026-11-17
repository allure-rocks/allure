# frozen_string_literal: true

module Federation
  module Safety
    # Creates and removes blocks and applies their privacy consequence: when a
    # remote actor or authority is blocked, every entitlement it delivered is
    # withdrawn with the `blocked` reason (docs/dev/FEDERATION.md). Public cached media
    # is retained exactly as on unfollow; unblocking does not restore
    # entitlements, because the withdrawal is the record of the decision.
    class Blocking
      def initialize(now: Time.current)
        @now = now
        @outbox_events = []
      end

      def block_domain!(domain:, created_by: nil)
        block = nil
        FederationDomainBlock.transaction do
          block = FederationDomainBlock.create!(domain:, created_by:)
          withdraw_entitlements!(remote_actors_for_domain(domain))
          cancel_open_deliveries!(block.domain)
        end
        Comments::Outbound.enqueue!(@outbox_events)
        block
      end

      def unblock_domain!(domain:)
        FederationDomainBlock.find_by(domain: domain.to_s.strip.downcase)&.destroy!
      end

      def block_actor!(actor_uri:, created_by: nil)
        block = nil
        FederationActorBlock.transaction do
          block = FederationActorBlock.create!(actor_uri:, created_by:)
          withdraw_entitlements!(remote_actors_for_actor_uri(actor_uri))
        end
        Comments::Outbound.enqueue!(@outbox_events)
        block
      end

      def unblock_actor!(actor_uri:)
        FederationActorBlock.find_by(actor_uri: actor_uri.to_s)&.destroy!
      end

      private

      # The sweep must reach actor rows whose host case differs from the
      # blocked domain: `~*` keeps the authority match case-insensitive while
      # the pattern only anchors the authority, never the path. A block without
      # a port reaches every subdomain and port, as `Blocks.covers?` does.
      def remote_actors_for_domain(domain)
        value = domain.to_s.strip.downcase
        return Actor.none if value.blank?

        pattern = if value.match?(Blocks::AUTHORITY_WITH_PORT)
          "\\Ahttps?://#{Regexp.escape(value)}(/|$)"
        else
          "\\Ahttps?://([^/]+\\.)?#{Regexp.escape(value)}(:[0-9]+)?(/|$)"
        end
        Actor.remote.where("uri ~* ?", pattern)
      end

      # Actor blocks are keyed on the host-folded URI, so the withdrawal sweep
      # has to find the same URI stored under any host casing.
      def remote_actors_for_actor_uri(actor_uri)
        value = Allure::Federation::Authority.normalize_uri(actor_uri)
        return Actor.none if value.blank?

        ids = Actor.remote.pluck(:id, :uri).filter_map do |id, uri|
          id if Allure::Federation::Authority.normalize_uri(uri) == value
        end
        Actor.where(id: ids)
      end

      def withdraw_entitlements!(actors)
        Notifications::Withdraw.new(actor: actors).call!
        # Their comments leave every thread here, hosted or received, and a
        # thread hosted here stops relaying them (PLAN_COMMENTS.md §7.6).
        removal = Comments::AuthorRemoval.new(actors:, reason: "blocked", now: @now)
        removal.call!
        @outbox_events.concat(removal.outbox_events)
        [ RemoteNote, RemoteSegment ].each do |model|
          model.where(actor_id: actors.select(:id)).find_each do |record|
            record.recipients.active.find_each { |recipient| recipient.withdraw!(reason: "blocked", at: @now) }
            RemoteMedia::Purge.new(owner: record, now: @now).call!
          end
        end
        withdraw_participations!(actors)
        Following.end_with!(actors, at: @now)
      end

      # Blocking a domain is also how an instance that disappeared is let go:
      # what was still waiting to reach it stops now instead of spending its
      # remaining attempts over the next days.
      def cancel_open_deliveries!(domain)
        FederationDelivery.where.not(status: FederationDelivery::TERMINAL_STATUSES).find_each do |delivery|
          next unless Blocks.covers?(domain, Allure::Federation::Authority.domain(delivery.inbox_url))

          delivery.cancel!(reason: "domain is blocked")
          delivery.outbox_event.reconcile_terminal_status!
        end
      end

      # A block ends every shared activity with the blocked actors, in both
      # directions, and tells nobody (docs/dev/SHARED-ACTIVITIES.md): invitations
      # received from them, and this instance's participations naming them.
      def withdraw_participations!(actors)
        RemoteParticipation.active.joins(:remote_note).where(remote_notes: { actor_id: actors.select(:id) })
          .find_each { |participation| Participations::RemoteWithdrawal.withdraw!(participation, at: @now) }
        WorkoutParticipation.active.where(participant_actor_id: actors.select(:id)).find_each do |participation|
          participation.update!(withdrawn_at: @now)
          Notifications::Withdraw.new(subject: participation).call!
        end
      end
    end
  end
end
