# frozen_string_literal: true

module Federation
  # The controlled account-deletion lifecycle: every active publication is
  # withdrawn first, then one signed actor Delete intent is created while the
  # actor is still current, and only then is the actor tombstoned. The key
  # retirement sweep waits for this event to become terminal.
  class ActorDeletion
    class InvalidActor < StandardError; end

    def initialize(actor:, now: Time.current)
      @actor = actor
      @now = now
    end

    def call!
      raise InvalidActor, "a local actor is required" unless @actor&.local?
      raise InvalidActor, "actor is already tombstoned" if @actor.tombstoned?
      raise InvalidActor, "local actor has no owner" unless @actor.user

      withdraw_publications!

      event = nil
      removal = Comments::AuthorRemoval.new(actors: @actor, reason: "actor_deleted", now: @now)
      Actor.transaction do
        @actor.with_lock do
          event = create_delete_event!
          # The account's comments on other workouts leave their threads with
          # it, and threads hosted here stop relaying them (docs/dev/COMMENTS.md
          # §7.6); its own workouts take theirs along.
          removal.call!
          @actor.tombstone!(at: @now)
        end
      end
      enqueue_expansion(event)
      Comments::Outbound.enqueue!(removal.outbox_events)
      event
    end

    private

    def withdraw_publications!
      user = @actor.user
      user.workouts.where(id: WorkoutPublication.active.select(:workout_id)).find_each do |workout|
        Workouts::PublicationDeletion.new(user:, workout:).call!
      end
      user.segments.joins(:active_publication).includes(:active_publication).find_each do |segment|
        Segments::PublicationWithdrawal.new(user:, segment:).call!
      end
    end

    # The follower URIs are read before tombstoning: an accepted follow is not
    # eligible once either side is tombstoned, and a followers-collection
    # audience would otherwise expand to nobody. Attempted recipients are
    # included so anyone who may already hold an object learns about the
    # account deletion.
    def create_delete_event!
      recipients = delete_recipients
      followers_uri = "#{@actor.uri}/followers"
      # The payload is what receivers actually parse; the explicit recipients
      # list and the followers collection must be on the wire, not only on the
      # outbox row (docs/dev/FEDERATION.md). Each destination receives only its own
      # actors from that list (`Outbox::WireAudience`).
      payload = {
        "type" => "Delete",
        "actor" => @actor.uri,
        "object" => Serializers::Tombstone.new(actor: @actor, at: @now).call,
        "recipients" => recipients,
        "to" => [ followers_uri ],
        "cc" => []
      }
      Outbox::EventBuilder.new(
        actor: @actor,
        subject_type: "Actor",
        subject_id: @actor.id,
        activity_type: "Delete",
        object_uri: @actor.uri,
        idempotency_key: "delete:#{@actor.uri}",
        payload:,
        audience: {
          "recipients" => recipients,
          "to" => [ followers_uri ],
          "cc" => []
        }
      ).call!
    end

    def delete_recipients
      followers = Following.accepted_followers_of(@actor)
        .includes(:follower_actor)
        .filter_map do |following|
          actor = following.follower_actor
          actor.uri if actor.remote? && !actor.tombstoned?
        end
      attempted = FederationDeliveryRecipient
        .joins(delivery: :outbox_event)
        .where(federation_outbox_events: { actor_id: @actor.id })
        .distinct
        .pluck(:actor_uri)

      (followers + attempted).uniq - [ @actor.uri ]
    end

    def enqueue_expansion(event)
      return unless event&.pending?

      Federation::ExpandOutboxEventJob.perform_later(event)
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name, actor_id: @actor.id })
    end
  end
end
