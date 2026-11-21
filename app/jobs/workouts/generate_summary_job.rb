# frozen_string_literal: true

module Workouts
  # Writes one workout's assistant summary (docs/dev/AI.md §6): it re-reads the
  # facts, calls the provider, verifies the answer, retries once at temperature
  # 0 when the verification refuses it, then writes the row. A terminal
  # rejection is `failed`; a provider outage is left to the queue's retries and
  # the recovery sweep.
  class GenerateSummaryJob < ApplicationJob
    queue_as :ai

    # The day's provider budget is spent: wait, the row stays pending.
    class BudgetExhaustedError < StandardError; end

    retry_on ActiveRecord::Deadlocked, ActiveRecord::ConnectionNotEstablished,
             ActiveRecord::SerializationFailure, wait: :polynomially_longer, attempts: 5
    retry_on BudgetExhaustedError, wait: 1.hour, attempts: 24
    retry_on Allure::Assistant::Client::UnavailableError,
             wait: ->(executions) { [ 30 * (2**executions), 3_600 ].min }, attempts: 5 do |job, _error|
      workout = job.arguments.first
      workout.assistant_summary&.update_columns(status: "failed", last_error: "unavailable",
                                                updated_at: Time.current)
    end
    discard_on ActiveJob::DeserializationError
    discard_on ActiveRecord::RecordNotFound

    def perform(workout)
      reason = SummaryEligibility.reason(workout)
      return drop_pending(workout) if %i[not_consented deactivated].include?(reason)
      return unless reason.nil?

      snapshot = SummaryFacts.new(workout).call
      row = workout.assistant_summary
      return unless row
      return if row.ready? && row.version == Allure::Insights::VERSION && row.facts_digest == snapshot.digest
      raise BudgetExhaustedError if SummaryRefresh.budget_exhausted?

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      outcome = SummaryGeneration.new.call(snapshot)
      record_metrics(outcome, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
      row = WorkoutSummary.find_by(id: row.id)
      return unless row

      row.assign_attributes(
        locale: snapshot.locale,
        version: Allure::Insights::VERSION,
        facts: snapshot.facts.map(&:to_h),
        facts_digest: snapshot.digest,
        requests_count: row.requests_count + outcome.calls,
        model: outcome.model
      )
      if outcome.verified&.valid?
        row.assign_attributes(status: "ready", title: outcome.verified.title,
                              sentences: outcome.verified.sentences, generated_at: Time.current,
                              last_error: nil)
      else
        row.assign_attributes(status: "failed", last_error: "invalid", generated_at: nil)
      end
      row.save!
    rescue Allure::Assistant::Client::InvalidRequestError => error
      count_request("rejected")
      fail_row(workout, "rejected")
      Rails.error.report(error, handled: true, context: { component: self.class.name })
    rescue Allure::Assistant::Client::UnavailableError
      count_request("unavailable")
      raise
    end

    private

    def record_metrics(outcome, duration)
      result = outcome.verified&.valid? ? "ok" : "invalid"
      Yabeda.allure.ai_requests_total.increment({ kind: "summary", result: }, by: outcome.calls)
      Yabeda.allure.ai_request_duration_seconds.measure({ kind: "summary" }, duration)
      Yabeda.allure.ai_tokens_total.increment({ kind: "summary", direction: "prompt" }, by: outcome.prompt_tokens)
      Yabeda.allure.ai_tokens_total.increment({ kind: "summary", direction: "completion" },
                                              by: outcome.completion_tokens)
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: "summary_metrics" })
    end

    def count_request(result)
      Yabeda.allure.ai_requests_total.increment({ kind: "summary", result: })
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: "ai_requests_total" })
    end

    def fail_row(workout, code)
      workout.assistant_summary&.update_columns(status: "failed", last_error: code, updated_at: Time.current)
    end

    def drop_pending(workout)
      row = workout.assistant_summary
      row.destroy if row&.pending?
    end
  end
end
