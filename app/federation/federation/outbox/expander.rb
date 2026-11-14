# frozen_string_literal: true

module Federation
  module Outbox
    class Expander
      PUBLIC_AUDIENCE = "https://www.w3.org/ns/activitystreams#Public"

      def initialize(event:, actor_resolver: nil, client: nil, now: Time.current)
        @event = event
        @now = now
        @client = client || Transport::Client.new
        @actor_resolver = actor_resolver || ActorResolver.new(client: @client, now:)
      end

      def call!
        # A publication Create stays `preparing` until its route image is
        # attached; expansion before that would send a Note without it.
        return [] if @event.preparing?
        return [] if @event.terminal?
        if publication_create_no_longer_sendable?
          @event.mark_cancelled!(reason: "publication is no longer active")
          return []
        end
        unless CommentSendability.sendable?(@event)
          @event.mark_cancelled!(reason: "comment is no longer in its thread")
          return []
        end
        return [] if awaiting_publication_expansion?

        deliveries = recipient_uris.filter_map do |actor_uri|
          add_recipient(actor_uri)
        end.uniq
        deliveries.each { enqueue_delivery(_1) }
        if deliveries.empty?
          @event.mark_complete!
        else
          @event.mark_expanded!
        end
        enqueue_waiting_secondary_events
        deliveries
      end

      private

      # The owner's comment and the host's relay ride on their publication
      # (PLAN_COMMENTS.md §9) and reach only that publication's recipients,
      # which exist once the publication's own Create expanded. Until then they
      # stay pending; that expansion enqueues them again.
      def awaiting_publication_expansion?
        publication = secondary_publication
        return false unless publication

        create_event = Workouts::PublicationWithdrawal.find_create_event(publication)
        create_event.present? && create_event.status.in?(%w[preparing pending])
      end

      def enqueue_waiting_secondary_events
        return unless publication_own_create?

        FederationOutboxEvent.where(
          workout_publication_id: @event.workout_publication_id, activity_type: %w[Create Announce Invite], status: "pending"
        ).where.not(id: @event.id).find_each do |event|
          Federation::ExpandOutboxEventJob.perform_later(event)
        end
      rescue StandardError => error
        Rails.error.report(error, handled: true, context: { component: self.class.name, outbox_event_id: @event.id })
      end

      def secondary_publication
        return unless @event.activity_type.in?(%w[Create Announce Invite]) && @event.subject_type == "WorkoutPublication"

        publication = WorkoutPublication.find_by(id: @event.workout_publication_id || @event.subject_id)
        publication if publication && publication.object_uri != @event.object_uri
      end

      def publication_own_create?
        @event.activity_type == "Create" && @event.subject_type == "WorkoutPublication" &&
          @event.workout_publication_id.present? && secondary_publication.nil?
      end

      def recipient_uris
        audience_values = Array(@event.audience["recipients"]) +
          Array(@event.audience["to"]) + Array(@event.audience["cc"])
        explicit = audience_values.select { |value| actor_uri?(value) }
        follower_collection = followers_collection_uri
        followers = if audience_values.include?(follower_collection)
          Following.accepted_followers_of(@event.actor).includes(:follower_actor)
            .filter_map { |following| following.follower_actor.uri if following.eligible_for_follower_access? }
        else
          []
        end
        (explicit + followers).uniq.reject { |uri| uri == @event.actor.uri }
      end

      # A publication's Create, and every Create or Announce riding on it,
      # stops with the publication.
      def publication_create_no_longer_sendable?
        return false unless @event.activity_type.in?(%w[Create Announce Invite])

        case @event.subject_type
        when "WorkoutPublication"
          !WorkoutPublication.active.exists?(id: @event.workout_publication_id || @event.subject_id)
        when "SegmentPublication"
          !SegmentPublication.active.exists?(id: @event.segment_publication_id || @event.subject_id)
        else
          false
        end
      end

      def actor_uri?(value)
        value.is_a?(String) && value != PUBLIC_AUDIENCE && value != followers_collection_uri
      end

      def add_recipient(actor_uri)
        return if Safety::Blocks.blocked?(actor_uri)

        actor = @actor_resolver.resolve(actor_uri, stale_ok: true)
        decision = Delivery::RecipientAuthorizer.new(event: @event, actor:, client: @client).call
        return unless decision.allowed?

        inbox_url = decision.inbox_url
        delivery = @event.deliveries.find_by(inbox_url:)
        unless delivery
          begin
            delivery = @event.deliveries.create!(inbox_url:)
          rescue ActiveRecord::RecordNotUnique
            delivery = @event.deliveries.find_by!(inbox_url:)
          end
        end
        recipient = delivery.recipients.find_or_initialize_by(actor_uri:)
        recipient.status = "authorized"
        recipient.save!
        delivery
      rescue ActorResolver::InvalidActor, ActorResolver::FetchError, Transport::SsrfGuard::UnsafeUri
        nil
      end

      def followers_collection_uri
        "#{@event.actor.uri}/followers"
      end

      def enqueue_delivery(delivery)
        return unless delivery.status.in?(%w[pending retrying])
        return unless delivery.next_attempt_at.blank? || delivery.next_attempt_at <= @now

        Federation::DeliverJob.perform_later(delivery)
      end
    end
  end
end
