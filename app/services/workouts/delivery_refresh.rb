# frozen_string_literal: true

module Workouts
  # Owner-triggered, publication-scoped delivery recovery: re-enqueues pending
  # intents and due deliveries for the publication and repairs event statuses.
  # Shares the global recovery semantics without touching other publications.
  class DeliveryRefresh
    Result = Data.define(:events_enqueued, :deliveries_enqueued, :events_repaired)

    def initialize(publication:, now: Time.current)
      @publication = publication
      @now = now
    end

    def call!
      raise ActiveRecord::RecordNotFound unless @publication.active?

      events = FederationOutboxEvent.where(workout_publication_id: @publication.id).order(:created_at, :id)
      events_enqueued = 0
      deliveries_enqueued = 0
      events_repaired = 0

      events.each do |event|
        if event.pending?
          Federation::ExpandOutboxEventJob.perform_later(event)
          events_enqueued += 1
        end
        event.deliveries.merge(FederationDelivery.due(@now)).find_each do |delivery|
          Federation::DeliverJob.perform_later(delivery)
          deliveries_enqueued += 1
        end
        event.with_lock do
          events_repaired += 1 if event.reconcile_terminal_status!
        end
      end

      Result.new(
        events_enqueued:,
        deliveries_enqueued:,
        events_repaired:
      )
    end
  end
end
