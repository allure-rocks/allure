# frozen_string_literal: true

module Federation
  module Delivery
    class ReconcileGone
      def initialize(delivery:, actor_resolver: nil, client: nil, now: Time.current)
        @delivery = delivery
        @now = now
        @client = client || Transport::Client.new
        @actor_resolver = actor_resolver || ActorResolver.new(client: @client, now:)
      end

      # One 410 recovery per delivery. Recipients are regrouped by their current
      # safe inbox so divergent personal inboxes never share a delivery
      # (docs/dev/PUBLISHING.md). Shared inboxes require explicit
      # restricted_shared_inbox capability, matching RecipientAuthorizer.
      def call!
        return :terminal unless @delivery.gone_recovery_used == false

        replacements = authorized_recipients.filter_map do |recipient|
          replacement_for(recipient)
        end
        if replacements.empty?
          @delivery.cancel!(reason: "remote inbox is gone", response_status: 410)
          return :cancelled
        end

        by_inbox = replacements.group_by { |replacement| replacement.fetch(:inbox_url) }
        sorted = by_inbox.sort_by { |_, group| -group.length }
        keep_inbox, keep_group = sorted.first
        @delivery.update!(
          inbox_url: keep_inbox,
          gone_recovery_used: true,
          status: "retrying",
          next_attempt_at: @now,
          lease_until: nil,
          last_error: nil
        )
        keep_uris = keep_group.map { |replacement| replacement.fetch(:actor_uri) }
        withdraw_recipients_except(keep_uris + moved_uris(sorted.drop(1)))
        sorted.drop(1).each do |new_inbox, group|
          split_delivery!(new_inbox, group.map { |replacement| replacement.fetch(:actor_uri) })
        end
        Federation::DeliverJob.perform_later(@delivery)
        :retry
      end

      private

      def authorized_recipients
        @delivery.recipients.authorized
      end

      def replacement_for(recipient)
        actor = @actor_resolver.resolve(recipient.actor_uri, refresh: true)
        return if actor.local? || actor.tombstoned?

        inbox_url = safe_replacement_inbox(actor)
        return if inbox_url.blank? || inbox_url == @delivery.inbox_url

        @client.validate_url(inbox_url)
        { actor_uri: recipient.actor_uri, inbox_url: inbox_url }
      rescue ActorResolver::InvalidActor, ActorResolver::FetchError, Transport::SsrfGuard::UnsafeUri
        nil
      end

      # Shared inboxes are only selected under explicit capability, never merely
      # because sharedInbox exists (docs/dev/PUBLISHING.md).
      def safe_replacement_inbox(actor)
        if actor.capability_profile == "restricted_shared_inbox" && actor.shared_inbox_url.present?
          actor.shared_inbox_url
        else
          actor.inbox_url
        end
      end

      def moved_uris(other_groups)
        other_groups.flat_map { |_, group| group.map { |replacement| replacement.fetch(:actor_uri) } }
      end

      def split_delivery!(new_inbox, actor_uris)
        event = @delivery.outbox_event
        new_delivery = event.deliveries.find_by(inbox_url: new_inbox)
        if new_delivery&.terminal?
          new_delivery.update!(status: "pending", next_attempt_at: nil, lease_until: nil, last_error: nil)
        end
        new_delivery ||= event.deliveries.create!(
          inbox_url: new_inbox,
          status: "retrying",
          next_attempt_at: @now
        )
        actor_uris.each do |actor_uri|
          authorized_recipients.find_by(actor_uri:)&.withdraw!
          moved = new_delivery.recipients.find_or_initialize_by(actor_uri:)
          moved.status = "authorized"
          moved.save!
        end
        Federation::DeliverJob.perform_later(new_delivery)
      rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid => error
        Rails.error.report(error, handled: true, context: { component: self.class.name })
      end

      def withdraw_recipients_except(actor_uris)
        authorized_recipients.where.not(actor_uri: actor_uris).find_each(&:withdraw!)
      end
    end
  end
end
