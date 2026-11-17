# frozen_string_literal: true

module Reactions
  # The single local write seam for reactions (docs/dev/REACTIONS.md). One
  # gesture means: add the reaction, withdraw it by repeating the same type, or
  # switch by withdrawing the old appreciation and creating a new reaction with
  # its own identity. The service authorizes the target, keeps the
  # one-active-reaction invariant, mints the ActivityPub identity, enqueues the
  # outbound Like or Undo for a received note, and keeps the owner's in-app
  # notification in step. Every row shares one transaction with its outbox
  # intent, so a reaction is never stored without the activity it announces.
  class Toggle
    class NotAllowed < StandardError; end
    class InvalidKind < StandardError; end

    def initialize(user:, target:, kind:)
      @user = user
      @target = target
      @kind = kind.to_s
      @outbox_events = []
    end

    def call!
      raise InvalidKind, "unknown reaction kind" unless Reaction::KINDS.include?(@kind)
      raise NotAllowed, "the target is not reactable" unless allowed?

      existing = active_reaction
      reaction = Reaction.transaction do
        if existing&.kind == @kind
          withdraw(existing)
        else
          # A switch keeps the owner's digest as it was: the account still
          # reacts, only the type changes, so nothing turns unread again.
          withdraw(existing, notify: false) if existing
          create(alert: existing.nil?)
        end
      end
      enqueue_expansions!
      reaction
    end

    private

    def actor
      @actor ||= Federation::ActorProvisioner.new(user: @user).call!
    rescue Federation::ActorProvisioner::IdentityConflict
      raise NotAllowed, "the account has no usable actor"
    end

    def target_attributes
      @target.is_a?(Workout) ? { workout: @target } : { remote_note: @target }
    end

    def active_reaction
      Reaction.active.find_by(actor:, **target_attributes)
    end

    def allowed?
      return false unless @user

      case @target
      when Workout then workout_allowed?
      when RemoteNote then note_allowed?
      else false
      end
    end

    # A self-reaction is not a social gesture: the owner sees the counts
    # without buttons (docs/dev/REACTIONS.md).
    def workout_allowed?
      return false if @target.user_id == @user.id

      # The publication serving the reader (docs/dev/PUBLISHING.md); reactions
      # stay on the workout, whichever version was read.
      publication = Workouts::PublicationResolver.new(workout: @target, user: @user).call
      return false unless publication

      @publication = publication
      Workouts::PublicationPolicy.new(
        publication:,
        principal: Workouts::PublicationPrincipal.browser(@user)
      ).allowed?(resource: :react)
    end

    def note_allowed?
      return false unless @target.active?

      Federation::RemoteNotePolicy.new(
        note: @target,
        principal: Workouts::PublicationPrincipal.browser(@user)
      ).allowed?(resource: :react)
    end

    def create(alert: true)
      uri, wire_key = reaction_identity
      reaction = Reaction.create!(actor:, kind: @kind, uri:, audience:, **target_attributes)
      if wire_key
        @outbox_events << Federation::Outbox::ReactionLike.new(
          reaction:, idempotency_key: wire_key
        ).call!
      end
      notify_owner(reaction, alert:)
      reaction
    end

    # The audience the reaction is named to (docs/dev/REACTIONS.md). While a
    # public version the reactor may read is live, the gesture reveals nothing
    # about them and is public, even when they were served a narrower version;
    # otherwise it keeps the audience of the version they read. A received
    # note's reaction keeps the note's audience.
    def audience
      return @target.audience if @target.is_a?(RemoteNote)
      return "public" if @publication.audience == "public"

      public_version = Workouts::PublicationResolver.new(workout: @target, user: @user, audience: "public").call
      public_version ? "public" : @publication.audience
    end

    # A reaction to a received note carries the URI of the Like that will be
    # delivered; a purely local one gets a local URI, exactly like a local
    # follow.
    def reaction_identity
      return [ Reactions::Wire.local_uri_for(actor:, target: @target), nil ] unless Reactions::Wire.federated?(@target)

      key = Reactions::Wire.key_for(target: @target)
      [ Reactions::Wire.uri_for(actor:, key:), key ]
    end

    def withdraw(reaction, notify: true)
      reaction.undo!
      if reaction.remote_target?
        @outbox_events << Federation::Outbox::ReactionUndo.new(reaction:).call!
      end
      withdraw_notification(reaction) if notify
      reaction
    end

    # Only a reaction on a local workout has a local owner to tell; a reaction
    # on a received note notifies the remote author through the delivered Like.
    def notify_owner(reaction, alert:)
      owner = reaction.workout&.user
      return unless owner

      Notifications::Create.new(
        user: owner,
        kind: "reaction",
        actor:,
        subject: reaction,
        alert:
      ).call!
    end

    def withdraw_notification(reaction)
      owner = reaction.workout&.user
      return unless owner

      Notifications::Withdraw.new(
        user: owner,
        kind: "reaction",
        subject: reaction
      ).call!
    end

    # Expansion runs after the row and its intent are committed; a queue error
    # never rolls back the gesture (the recovery sweep picks pending events up).
    def enqueue_expansions!
      @outbox_events.each do |event|
        next unless event.pending?

        Federation::ExpandOutboxEventJob.perform_later(event)
      rescue StandardError => error
        Rails.error.report(error, handled: true, context: { component: self.class.name })
      end
    end
  end
end
