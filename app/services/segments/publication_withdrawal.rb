# frozen_string_literal: true

module Segments
  # Withdraws a course publication: cancels unattempted Create deliveries,
  # emits an explicit-recipient Delete, and marks the publication deleted.
  # Mirrors Workouts::PublicationWithdrawal
  # (PLAN_SEGMENTS_FEDERATION.md §9.4).
  class PublicationWithdrawal
    ATTEMPTED_DELIVERY_STATUSES = %w[delivered failed delivering retrying reconciling].freeze
    RECIPIENT_STATUSES = %w[authorized withdrawn].freeze

    Result = Data.define(:publication, :delete_event, :created)

    def initialize(user:, segment: nil, publication: nil, operator: false)
      @user = user
      @segment = segment
      @given_publication = publication
      @operator = operator
    end

    def call!
      result = persist!
      self.class.enqueue_expansion(result.delete_event)
      result
    end

    # Durable withdrawal without enqueueing, so callers that must atomically
    # combine withdrawal with source destruction can run this inside their own
    # transaction and enqueue only after commit.
    def persist!
      publication = resolve_publication!
      authorize!(publication)

      if publication.deleted?
        delete_event = self.class.find_delete_event(publication)
        return Result.new(publication:, delete_event:, created: false)
      end

      actor = publication.actor
      delete_event = nil
      created = false

      SegmentPublication.transaction(requires_new: true) do
        actor.with_lock do
          lock_segment_source(publication)
          publication.lock!
          if publication.deleted?
            delete_event = self.class.find_delete_event(publication)
            created = false
          else
            create_event = self.class.find_create_event(publication)
            recipient_uris = self.class.recipient_uris_for(create_event)
            self.class.cancel_unattempted!(create_event)
            delete_event, created = find_or_create_delete_event!(publication, actor, recipient_uris)
            publication.mark_deleted!
            reconcile_create_event!(create_event, recipient_uris)
          end
        end
      end

      Result.new(publication:, delete_event:, created:)
    end

    def self.find_create_event(publication)
      FederationOutboxEvent.find_by(
        actor: publication.actor,
        subject_type: "SegmentPublication",
        subject_id: publication.id,
        segment_publication_id: publication.id,
        object_uri: publication.object_uri,
        activity_type: "Create"
      )
    end

    # Every logical recipient whose Create delivery made any network attempt
    # must receive Delete. A delivery cancelled after claim still may have
    # reached the remote on an earlier attempt; never-attempted
    # pending->cancelled rows are not included.
    def self.recipient_uris_for(create_event)
      return [] unless create_event

      deliveries = create_event.deliveries.includes(:recipients).to_a
      attempted = deliveries.select do |delivery|
        delivery.status.in?(ATTEMPTED_DELIVERY_STATUSES) ||
          (delivery.status == "cancelled" && delivery.attempts.to_i.positive?)
      end
      attempted.flat_map do |delivery|
        delivery.recipients.select { |recipient| recipient.status.in?(RECIPIENT_STATUSES) }.map(&:actor_uri)
      end.uniq
    end

    def self.cancel_unattempted!(create_event)
      return unless create_event

      create_event.deliveries.each do |delivery|
        next unless delivery.status == "pending"

        delivery.update!(
          status: "cancelled",
          next_attempt_at: nil,
          lease_until: nil,
          last_error: "segment publication deleted"
        )
      end
    end

    def self.enqueue_expansion(event)
      return unless Allure::Federation::Config.enabled? && event&.pending?

      Federation::ExpandOutboxEventJob.perform_later(event)
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: name })
    end

    private

    def resolve_publication!
      return @given_publication.reload if @given_publication
      raise ActiveRecord::RecordNotFound unless @segment

      @segment.association(:active_publication).reset
      active = @segment.active_publication
      return active if active

      @segment.segment_publications.deleted.order(created_at: :desc, id: :desc).first ||
        raise(ActiveRecord::RecordNotFound)
    end

    # The owner path is the default. `operator: true` is only honored for an
    # actual instance operator, so administration takedown can never become a
    # general authorization bypass (PLAN_ADMIN.md §4.4).
    def authorize!(publication)
      return if operator?

      owner_id = publication.segment&.user_id || publication.actor&.user_id
      raise ActiveRecord::RecordNotFound unless owner_id && owner_id == @user.id
    end

    def operator?
      @operator && @user.respond_to?(:instance_operator?) && @user.instance_operator?
    end

    def lock_segment_source(publication)
      segment = publication.segment
      if @segment && segment && @segment.id == segment.id
        @segment.with_lock { }
      elsif segment
        segment.with_lock { }
      elsif @segment
        @segment.with_lock { }
      end
    end

    def self.find_delete_event(publication)
      FederationOutboxEvent.find_by(
        subject_type: "SegmentPublication",
        subject_id: publication.id,
        segment_publication_id: publication.id,
        object_uri: publication.object_uri,
        activity_type: "Delete"
      )
    end

    def find_or_create_delete_event!(publication, actor, recipient_uris)
      existing = self.class.find_delete_event(publication)
      return [ existing, false ] if existing

      begin
        event = Federation::Outbox::EventBuilder.new(
          actor:,
          subject_type: "SegmentPublication",
          subject_id: publication.id,
          segment_publication_id: publication.id,
          activity_type: "Delete",
          object_uri: publication.object_uri,
          idempotency_key: "segment_publication:delete:#{publication.object_uri}",
          payload: {
            "type" => "Delete",
            "actor" => actor.uri,
            "object" => publication.object_uri,
            "to" => recipient_uris,
            "cc" => []
          },
          audience: { "recipients" => recipient_uris, "to" => recipient_uris, "cc" => [] }
        ).call!
        [ event, true ]
      rescue Federation::Outbox::EventBuilder::IdentityConflict
        [ find_delete_event(publication), false ]
      end
    end

    def reconcile_create_event!(create_event, recipient_uris)
      return unless create_event
      return if recipient_uris.any?
      return if create_event.terminal?

      create_event.mark_cancelled!(reason: "segment publication deleted before any delivery attempt")
    end
  end
end
