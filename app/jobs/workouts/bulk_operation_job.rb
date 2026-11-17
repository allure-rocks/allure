# frozen_string_literal: true

module Workouts
  # Executes a confirmed bulk operation (docs/dev/BULK-ACTIONS.md): the queued
  # items are applied in position order, BATCH_SIZE per invocation, and the job
  # re-enqueues itself while work remains, so a long operation never holds a
  # worker. It is resumable (queued items are the cursor), idempotent per item
  # (each service tolerates an already-applied state), cancellable between
  # items, and serialized per account.
  class BulkOperationJob < ApplicationJob
    BATCH_SIZE = 25

    queue_as :default
    limits_concurrency key: ->(operation_id, user_id, **) { "workout-bulk-#{user_id}" }, duration: 2.hours

    retry_on ActiveRecord::Deadlocked, ActiveRecord::ConnectionNotEstablished,
             ActiveRecord::SerializationFailure, wait: :polynomially_longer, attempts: 5

    def perform(operation_id, user_id)
      operation = WorkoutBulkOperation.find_by(id: operation_id, user_id:)
      return if operation.nil? || operation.terminal?

      return operation.cancel_remaining! if cancellation_requested?(operation)

      operation.start! if operation.status == "queued"
      process_batch(operation)
    rescue StandardError
      # Mirrors ImportBatchJob: an unexpected job-level failure is terminal and
      # visible on the progress page. A retry then finds a terminal row and
      # does nothing.
      operation&.mark_failed! if operation && !operation.terminal?
      raise
    end

    private

    def process_batch(operation)
      operation.items.queued.in_order.limit(BATCH_SIZE).each do |item|
        return operation.cancel_remaining! if cancellation_requested?(operation)

        apply(operation, item)
      end

      if cancellation_requested?(operation)
        operation.cancel_remaining!
      elsif operation.items.queued.exists?
        self.class.perform_later(operation.id, operation.user_id)
      else
        operation.complete!
      end
    end

    # Every failure mode is per item: a broken workout never stops the batch,
    # and each outcome is a translated code, never a raw message.
    def apply(operation, item)
      workout = item.workout
      return item.mark_skipped!("workout_missing") if workout.nil?

      case operation.operation
      when "sport_change" then apply_sport_change(operation, item, workout)
      when "delete" then apply_delete(operation, item, workout)
      end
    rescue Workouts::SportChange::MissingOriginalFile
      item.mark_skipped!("missing_original_file")
    rescue Workouts::SportChange::ReanalysisFailed
      item.mark_failed!("reanalysis_failed")
    rescue ActiveRecord::RecordNotFound
      item.mark_skipped!("workout_missing")
    rescue StandardError => error
      Rails.error.report(error, handled: true,
        context: {
          component: self.class.name,
          workout_bulk_operation_id: operation.id,
          workout_id: item.workout_id
        })
      item.mark_failed!("unknown")
    end

    def apply_sport_change(operation, item, workout)
      sport = Sport.find_by(id: operation.parameters["sport_id"])
      return item.mark_failed!("unknown") if sport.nil?

      changed = workout.sport_id != sport.id
      SportChange.new(workout:, sport:).call!
      Webhooks::Events.workout_updated(workout, [ "sport" ]) if changed
      item.mark_modified!
    end

    def apply_delete(operation, item, workout)
      WorkoutDeletion.new(user: operation.user, workout:).call!
      item.mark_modified!
    end

    def cancellation_requested?(operation)
      operation.class.where(id: operation.id).pick(:cancellation_requested_at).present?
    end
  end
end
