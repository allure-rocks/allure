# frozen_string_literal: true

require "json"
require "uri"

module Federation
  module Delivery
    class Deliver
      # 401 is worth another try: the receiver usually refused because it
      # could not fetch our key at that moment (Mastodon retries it too).
      RETRYABLE_STATUSES = [ 401, 408, 409, 425, 429 ].freeze

      def initialize(delivery:, client: nil, actor_resolver: nil, now: Time.current)
        @delivery = delivery
        @now = now
        @client = client || Transport::Client.new
        @actor_resolver = actor_resolver || ActorResolver.new(client: @client, now:)
      end

      def call!
        return unless @delivery.claim!(now: @now)
        reauthorize_recipients!
        return cancel_without_recipient unless authorized_recipient?
        return cancel_for_publication_state unless event_sendable?
        return if wait_for_predecessor?

        response = send_request
        handle_response(response)
      rescue Transport::SsrfGuard::UnsafeUri => error
        @delivery.fail!(error: error)
      rescue Transport::Client::TooManyRedirects, Transport::Client::UnsafeRedirect
        @delivery.fail!(error: "inbox redirected; a signed POST is not followed")
      rescue Transport::Client::ResponseTooLarge, Transport::Client::ResponseTimeout,
             Transport::Client::NetworkError => error
        retry_delivery(error:)
      ensure
        refresh_event_status
      end

      private

      def send_request
        uri = URI.parse(@delivery.inbox_url)
        body = Outbox::CanonicalJson.call(Outbox::WireAudience.for_delivery(@delivery))
        headers = Federation::Signature::Signer.new(actor: @delivery.outbox_event.actor).call(
          method: "POST",
          path: uri.request_uri,
          host: host_header(uri),
          body:,
          content_type: Allure::Federation::MediaTypes::ACTIVITY_PUB,
          date: @now.httpdate
        )
        # The signature covers this host and path: a redirected POST would be
        # refused wherever it landed, so an inbox that redirects is not
        # followed (Mastodon does the same).
        @client.post(@delivery.inbox_url, body:, headers:, max_redirects: 0)
      rescue URI::InvalidURIError => error
        raise Transport::SsrfGuard::UnsafeUri, error.message
      end

      def handle_response(response)
        status = response.status.to_i
        return @delivery.mark_delivered!(response_status: status, at: @now) if status.between?(200, 299)
        return reconcile_gone if status == 410
        return retry_delivery(error: "remote HTTP #{status}", response_status: status) if retryable_status?(status)

        @delivery.fail!(error: "permanent remote HTTP #{status}", response_status: status)
      end

      def reconcile_gone
        @delivery.mark_reconciling!(response_status: 410)
        result = Federation::Delivery::ReconcileGone.new(
          delivery: @delivery, actor_resolver: @actor_resolver, client: @client, now: @now
        ).call!
        @delivery.fail!(error: "remote inbox remained gone", response_status: 410) if result == :terminal
      end

      def retry_delivery(error:, response_status: nil)
        if @delivery.retry!(error:, response_status:, now: @now)
          Federation::DeliverJob.set(wait_until: @delivery.next_attempt_at).perform_later(@delivery)
        end
      end

      def authorized_recipient?
        @delivery.recipients.authorized.exists?
      end

      def event_sendable?
        event = @delivery.outbox_event
        return false if event.status == "cancelled"
        return false unless Outbox::CommentSendability.sendable?(event)

        case event.subject_type
        when "WorkoutPublication"
          publication = WorkoutPublication.find_by(id: event.workout_publication_id || event.subject_id)
          publication_state_sendable?(publication, event)
        when "SegmentPublication"
          publication = SegmentPublication.find_by(id: event.segment_publication_id || event.subject_id)
          publication_state_sendable?(publication, event)
        else
          true
        end
      end

      # A Create or an Announce must still have its active subject; a Delete or
      # an Undo only needs the retained identity.
      def publication_state_sendable?(publication, event)
        return false unless publication
        return true unless event.activity_type.in?(%w[Create Announce Invite])

        publication.active?
      end

      # Reauthorizes immediately before POST (docs/dev/PUBLISHING.md) and recalculates
      # the safe destination. A stale inbox_url is never used: single-recipient
      # or unanimous moves update in place, divergent inboxes split so each
      # delivery keeps one destination.
      def reauthorize_recipients!
        event = @delivery.outbox_event
        decisions = {}
        @delivery.recipients.authorized.find_each do |recipient|
          actor = Actor.find_by(uri: recipient.actor_uri)
          if actor.nil? && !event.subject_type.in?(%w[WorkoutPublication SegmentPublication])
            next
          end
          decision = Delivery::RecipientAuthorizer.new(event:, actor:, client: @client).call
          unless decision.allowed?
            recipient.withdraw!
            next
          end
          decisions[recipient.id] = decision.inbox_url if decision.inbox_url.present?
        end
        reconcile_inbox_moves!(decisions) if decisions.any?
      end

      def reconcile_inbox_moves!(decisions)
        @delivery.reload
        authorized = @delivery.recipients.authorized.to_a
        return if authorized.empty?

        by_inbox = authorized.group_by { |recipient| decisions[recipient.id] || @delivery.inbox_url }
        return if by_inbox.keys.compact == [ @delivery.inbox_url ] && by_inbox.size == 1

        # Keep the largest group in the current delivery to minimize moves.
        sorted = by_inbox.sort_by { |_, recipients| -recipients.length }
        keep_inbox, _keep_recipients = sorted.first
        if keep_inbox != @delivery.inbox_url
          @delivery.update!(inbox_url: keep_inbox)
        end
        sorted.drop(1).each do |new_inbox, recipients|
          next if new_inbox.blank?

          new_delivery = event_delivery_for(new_inbox)
          recipients.each do |recipient|
            recipient.withdraw!
            moved = new_delivery.recipients.find_or_initialize_by(actor_uri: recipient.actor_uri)
            moved.status = "authorized"
            moved.save!
          end
          enqueue_moved_delivery!(new_delivery)
        end
      end

      def event_delivery_for(inbox_url)
        event = @delivery.outbox_event
        existing = event.deliveries.find_by(inbox_url:)
        return existing unless existing.nil? || existing.terminal?

        if existing&.terminal?
          existing.update!(status: "pending", next_attempt_at: nil, lease_until: nil, last_error: nil)
          return existing
        end

        event.deliveries.create!(inbox_url:, status: "pending")
      rescue ActiveRecord::RecordNotUnique
        found = event.deliveries.find_by!(inbox_url:)
        if found.terminal?
          found.update!(status: "pending", next_attempt_at: nil, lease_until: nil, last_error: nil)
        end
        found
      end

      def enqueue_moved_delivery!(delivery)
        return unless delivery.status.in?(%w[pending retrying])
        return unless delivery.next_attempt_at.blank? || delivery.next_attempt_at <= @now

        Federation::DeliverJob.perform_later(delivery)
      rescue StandardError => error
        Rails.error.report(error, handled: true, context: { component: self.class.name })
      end

      def wait_for_predecessor?
        event = @delivery.outbox_event
        predecessor = predecessor_for(event)
        return false unless predecessor

        recipient_uris = @delivery.recipients.where(status: %w[authorized withdrawn]).pluck(:actor_uri)
        return false if recipient_uris.empty?

        pending = recipient_uris.any? do |uri|
          scope = predecessor.deliveries.joins(:recipients)
            .where(federation_delivery_recipients: { actor_uri: uri })
          next false if scope.empty?

          scope.where.not(status: %w[delivered cancelled failed]).exists?
        end
        return false unless pending

        if @delivery.retry!(error: "waiting for Create predecessor", now: @now)
          Federation::DeliverJob.set(wait_until: @delivery.next_attempt_at).perform_later(@delivery)
        end
        true
      end

      # A Delete waits for its own Create. A secondary Create or Announce — an
      # owner's comment or a relayed one riding on a publication — waits for
      # the publication's Create to reach the same recipient, or the comment
      # would arrive before the note it answers and be refused for good; a
      # secondary Undo waits for the activity it undoes (PLAN_COMMENTS.md §9).
      def predecessor_for(event)
        case event.activity_type
        when "Delete"
          FederationOutboxEvent.where(
            actor_id: event.actor_id, object_uri: event.object_uri, activity_type: "Create"
          ).order(created_at: :desc).first
        when "Create", "Announce", "Invite"
          secondary_predecessor(event)
        when "Undo"
          Delivery::RecipientAuthorizer.undone_event_for(event) if event.subject_type == "WorkoutPublication"
        end
      end

      def secondary_predecessor(event)
        return unless event.subject_type == "WorkoutPublication"

        publication = WorkoutPublication.find_by(id: event.workout_publication_id || event.subject_id)
        return unless publication && publication.object_uri != event.object_uri

        Workouts::PublicationWithdrawal.find_create_event(publication)
      end

      def retryable_status?(status)
        RETRYABLE_STATUSES.include?(status) || status.between?(500, 599)
      end

      def cancel_without_recipient
        @delivery.cancel!(reason: "no authorized delivery recipient")
      end

      def cancel_for_publication_state
        @delivery.cancel!(reason: "outbox event is no longer sendable")
      end

      def refresh_event_status
        event = @delivery.outbox_event
        return unless event.persisted?

        event.reconcile_terminal_status!
      end

      def host_header(uri)
        default_port = uri.scheme == "https" ? 443 : 80
        uri.port == default_port ? uri.host : "#{uri.host}:#{uri.port}"
      end
    end
  end
end
