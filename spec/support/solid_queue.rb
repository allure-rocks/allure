# frozen_string_literal: true

# Solid Queue rows live in the separate queue database, so examples that touch
# the administration jobs panel clear them explicitly: transactional fixtures
# are not guaranteed to wrap every pool, and stale failures would otherwise
# leak between examples.
#
# SolidQueue::Job's after_create callback prepares a ready or scheduled
# execution automatically; the helpers model the real states instead of adding
# executions by hand.
module SolidQueueHelpers
  TABLES = %w[
    solid_queue_batch_executions
    solid_queue_failed_executions solid_queue_ready_executions
    solid_queue_scheduled_executions solid_queue_claimed_executions
    solid_queue_blocked_executions solid_queue_recurring_executions
    solid_queue_jobs solid_queue_batches
    solid_queue_pauses solid_queue_processes solid_queue_recurring_tasks
    solid_queue_semaphores
  ].freeze

  def clear_solid_queue!
    TABLES.each { |table| SolidQueue::Record.connection.execute("DELETE FROM #{table}") }
  end

  def create_ready_job(queue_name: "default", class_name: "Workouts::ReanalyzeJob")
    SolidQueue::Job.create!(queue_name:, class_name:, arguments: {})
  end

  def create_scheduled_job(queue_name: "default", class_name: "Workouts::ReanalyzeJob", at: 1.hour.from_now)
    SolidQueue::Job.create!(queue_name:, class_name:, arguments: {}, scheduled_at: at)
  end

  # A failed job has no ready execution in the real lifecycle: the claimed
  # execution is replaced by the failure.
  def create_failed_job(class_name: "Workouts::ReanalyzeJob", queue_name: "default", message: "boom")
    job = create_ready_job(queue_name:, class_name:)
    job.ready_execution&.delete
    SolidQueue::FailedExecution.create!(job:, error: { "exception_class" => "RuntimeError", "message" => message })
    job
  end
end

RSpec.configure do |config|
  config.include SolidQueueHelpers
end
