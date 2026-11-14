# frozen_string_literal: true

module Participations
  # Follows a source's changes on its attached credit rows (PLAN_TOGETHER.md
  # §6.2): an edit, a re-analysis, a sport change, a climb rebuild. One run at
  # a time per source.
  class CreditSyncJob < ApplicationJob
    queue_as :default

    limits_concurrency key: ->(source) { "credit-sync-#{source.id}" }, duration: 5.minutes
    retry_on ActiveRecord::Deadlocked, ActiveRecord::ConnectionNotEstablished,
             wait: :polynomially_longer, attempts: 5
    discard_on ActiveJob::DeserializationError

    def self.nudge(source)
      perform_later(source) if source.recording? && source.credit_rows.exists?
    end

    def perform(source)
      source.credit_rows.find_each { |row| CreditSync.new(row).call }
    end
  end
end
