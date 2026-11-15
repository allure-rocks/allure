# frozen_string_literal: true

module Workouts
  # Activates one scheduled publication (docs/dev/DELAYED-PUBLISHING.md): the
  # frozen snapshot becomes visible, the Create intent is created atomically
  # with the transition, and delivery starts once the route image is ready.
  #
  # Called by the delayed job, by the owner's "publish now" (`force:`), and by
  # the recovery sweep. Idempotent: a publication that is not scheduled is left
  # untouched, and a job that fires before the planned moment re-enqueues
  # itself.
  class ScheduledPublicationActivation
    Result = Data.define(:publication, :outbox_event)
    SWEEP_LIMIT = 500

    def initialize(publication:, now: Time.current, force: false, notify: true)
      @publication = publication
      @now = now
      @force = force
      @notify = notify
    end

    # Enqueues the activation job for `scheduled_for`. A lost enqueue is
    # recovered by the sweep, so this never strands a publication.
    def self.enqueue_job(publication)
      Workouts::ActivateScheduledPublicationJob
        .set(wait_until: publication.scheduled_for)
        .perform_later(publication)
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: name, workout_publication_id: publication.id })
    end

    # Immediate publishing (docs/dev/DELAYED-PUBLISHING.md): activates the frozen
    # publication in the request path. The job is enqueued first as a fallback —
    # it no-ops on an active publication and recovers an activation failure that
    # left the row scheduled, so nothing is ever stranded. The owner is acting
    # right now, so no activation notification is sent: only the automatic
    # activation needs to tell them their hold ended.
    def self.activate_now(publication)
      enqueue_job(publication)
      new(publication:, force: true, notify: false).call!
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: name, workout_publication_id: publication.id })
    end

    # Activates every due scheduled publication; a lost enqueue or instance
    # downtime is recovered here, never stranded.
    def self.sweep(now: Time.current, limit: SWEEP_LIMIT)
      activated = 0
      WorkoutPublication.due_for_activation(now).order(:scheduled_for, :id).limit(limit).each do |publication|
        result = new(publication:, now:).call!
        activated += 1 if result.is_a?(Result)
      rescue StandardError => error
        Rails.error.report(error, handled: true, context: { component: name, workout_publication_id: publication.id })
        next
      end
      activated
    end

    def call!
      return nil unless @publication.scheduled?
      return nil if owner_deactivated?
      return defer if @publication.scheduled_for > @now && !@force

      event = nil
      activated = nil
      WorkoutPublication.transaction do
        @publication.activate!(at: @now)
        # Lost the race against cancellation or a concurrent activation.
        next unless @publication.active?

        event = create_outbox_event!
        activated = @publication
      end
      return nil unless activated

      Webhooks::Events.publication_activated(activated)
      enqueue_tail(activated, event)
      notify(activated) if @notify
      Result.new(publication: activated, outbox_event: event)
    end

    private

    # An account in its deletion window runs nothing on its behalf
    # (PLAN_ACCOUNT.md §4.2): a due publication waits there, its deliveries
    # being refused by the publication policy anyway, and the purge cancels it
    # with its workout. The recovery sweep activates it after a cancellation,
    # when the owner is available again.
    def owner_deactivated?
      @publication.actor&.user&.deletion_scheduled? || false
    end

    def defer
      self.class.enqueue_job(@publication)
      :deferred
    end

    def create_outbox_event!
      status = @publication.route_image_pending? ? "preparing" : "pending"
      Federation::Outbox::PublicationCreate.new(publication: @publication).intent!(status:)
    end

    # The owner caused the event, so the notification is actorless; the self
    # skip in Notifications::Create only applies when an actor is present.
    def notify(publication)
      owner = publication.workout&.user
      return unless owner

      Notifications::Create.new(
        user: owner,
        kind: "publication_activated",
        subject: publication,
        payload: { "audience" => publication.audience }
      ).call!
    end

    def enqueue_tail(publication, event)
      if publication.route_image_pending?
        enqueue_route_image(publication)
      else
        enqueue_expansion(event)
      end
    end

    def enqueue_route_image(publication)
      Workouts::RenderPublicationRouteImageJob.perform_later(publication)
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name, workout_publication_id: publication.id })
    end

    def enqueue_expansion(event)
      return unless Allure::Federation::Config.enabled? && event&.pending?

      Federation::ExpandOutboxEventJob.perform_later(event)
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name, outbox_event_id: event&.id })
    end
  end
end
