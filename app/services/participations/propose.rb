# frozen_string_literal: true

module Participations
  # The owner's invitation seam (PLAN_TOGETHER.md §5, §7). A local account
  # needs an accepted follow in either direction; it gets the pending credit
  # with the owner's confirmation and a notice. A remote Allure account
  # (lot 4) must already hold the workout's active publication — its delivery
  # of the publication's Create is live and it follows the owner — and that
  # publication must share the figures a credit row is built from; it gets an
  # `Invite` addressed to it alone, riding on that publication. Repeating an
  # invitation for a live pair is a no-op; a refused pair stays refused.
  class Propose
    class NotAllowed < StandardError; end

    # The figures a remote participant's credit row is built from: a
    # publication hiding one of them cannot carry a remote invitation.
    REMOTE_REQUIRED_METRICS = %w[distance duration moving_time ascent descent average_speed].freeze

    def initialize(user:, workout:, target:)
      @user = user
      @workout = workout
      @target = target
    end

    def call!
      raise NotAllowed, "only the owner can invite" unless @workout.user_id == @user.id
      raise NotAllowed, "only a recording can be shared" unless @workout.recording?

      owner_actor = owner_actor!
      target_actor = resolve_target!
      raise NotAllowed, "self-participation is not a shared activity" if target_actor.user_id == @user.id

      target_actor.local? ? propose_local(owner_actor, target_actor) : propose_remote(owner_actor, target_actor)
    end

    private

    def propose_local(owner_actor, target_actor)
      raise NotAllowed, "an invitation needs an accepted follow" unless followed?(owner_actor, target_actor)

      existing = live_participation(target_actor)
      return existing if existing

      participation = @workout.workout_participations.create!(
        participant_actor: target_actor,
        kind: "credit",
        origin: "invitation",
        owner_confirmed_at: Time.current
      )
      notify_requested(participation, owner_actor)
      participation
    end

    def propose_remote(owner_actor, target_actor)
      publication = held_publication(target_actor)
      raise NotAllowed, "the account does not hold this workout's publication" unless publication
      unless Following.accepted_between(follower_actor: target_actor, followed_actor: owner_actor).exists?
        raise NotAllowed, "an invitation needs the account to follow the owner"
      end
      raise NotAllowed, "the publication does not share the credited figures" unless credited_figures_shared?(publication)

      existing = live_participation(target_actor)
      return existing if existing && existing.workout_publication&.active?

      # An invitation riding on a publication that is gone cannot be answered
      # any more; a new one rides on the current publication, and the invited
      # instance re-attaches a credit it kept (PLAN_TOGETHER.md §7.6).
      if existing
        existing.update!(withdrawn_at: Time.current)
        Notifications::Withdraw.new(subject: existing).call!
      end

      participation = nil
      event = nil
      WorkoutParticipation.transaction do
        participation = @workout.workout_participations.create!(
          participant_actor: target_actor,
          kind: "credit",
          origin: "invitation",
          owner_confirmed_at: Time.current,
          workout_publication: publication
        )
        participation.reload
        event = Federation::Outbox::ParticipationInvite.new(participation:, publication:).call!
        participation.update!(wire_activity_uri: event.activity_uri)
      end
      Comments::Outbound.enqueue!(event)
      participation
    end

    # Live-scoped: a withdrawn row must never shadow a live one. An unscoped
    # lookup could return the withdrawn row, miss both guards, and violate
    # the partial unique index on the live pair (a 500 from the UI). A
    # declined row is live on purpose, so the terminal refusal still fires.
    def live_participation(target_actor)
      existing = @workout.workout_participations.live.find_by(participant_actor: target_actor)
      raise NotAllowed, "a refusal is terminal for this pair" if existing&.declined?

      existing
    end

    # The narrowest active publication whose Create the remote account was
    # authorized for and is still being, or was, delivered: the one it holds
    # (PLAN_AUDIENCES.md §5). An invitation rides on it.
    def held_publication(target_actor)
      @workout.active_publications.find do |publication|
        create_event = Workouts::PublicationWithdrawal.find_create_event(publication)
        next false unless create_event

        FederationDeliveryRecipient.joins(:delivery)
          .where(actor_uri: target_actor.uri, status: "authorized")
          .where(federation_deliveries: {
            outbox_event_id: create_event.id,
            status: Federation::Delivery::RecipientAuthorizer::LIVE_PUBLICATION_DELIVERY_STATUSES
          })
          .exists?
      end
    end

    def credited_figures_shared?(publication)
      metrics = publication.metrics
      REMOTE_REQUIRED_METRICS.all? { |key| !metrics[key].nil? }
    end

    def resolve_target!
      actor = Federation::TargetResolver.new.call!(@target)
      raise NotAllowed, "the target has no account" if actor.local? && actor.user.nil?

      actor
    # A remote handle that cannot be resolved — unknown, unreachable, or
    # refused by the outbound guard — is a refusal, never an error page.
    rescue Federation::TargetResolver::InvalidTarget,
           Federation::WebFingerResolver::FetchError, Federation::ActorResolver::FetchError,
           Federation::Transport::SsrfGuard::UnsafeUri, Federation::Transport::Client::NetworkError => error
      raise NotAllowed, error.message
    end

    def owner_actor!
      Federation::ActorProvisioner.new(user: @user).call!
    rescue Federation::ActorProvisioner::IdentityConflict
      raise NotAllowed, "the account has no usable actor"
    end

    def followed?(owner_actor, target_actor)
      Following.accepted_between(follower_actor: owner_actor, followed_actor: target_actor)
        .or(Following.accepted_between(follower_actor: target_actor, followed_actor: owner_actor))
        .exists?
    end

    def notify_requested(participation, owner_actor)
      Notifications::Create.new(
        user: participation.participant_user,
        kind: "participation_requested",
        actor: owner_actor,
        subject: participation
      ).call!
    end
  end
end
