class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError

  # A bulk import's enrichments run behind new outings (BacklogPriority).
  before_enqueue { self.priority = BacklogPriority::PRIORITY if priority.nil? && BacklogPriority.active? }
  around_perform { |job, block| BacklogPriority.enqueue(active: BacklogPriority.backlog?(job), &block) }
end
