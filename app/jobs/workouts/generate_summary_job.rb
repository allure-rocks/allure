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

    Outcome = Data.define(:verified, :model, :calls)

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

      outcome = generate(snapshot)
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
      fail_row(workout, "rejected")
      Rails.error.report(error, handled: true, context: { component: self.class.name })
    end

    private

    # One attempt, then one retry at temperature 0 when the verification
    # refused the answer (or the answer was not usable JSON).
    def generate(snapshot)
      prompt = Allure::Insights::Prompt.new(facts: snapshot.facts, locale: snapshot.locale)
      verifier = Allure::Insights::Verifier.new(snapshot.facts)
      client = Allure::Assistant::Config.client
      calls = 0
      model = nil
      verified = nil
      2.times do |attempt|
        begin
          result = client.complete(
            system: prompt.system,
            user: attempt.zero? ? prompt.user : retry_user(prompt, verified),
            schema: Allure::Insights::SummarySchema.call,
            schema_name: Allure::Insights::Prompt::SCHEMA_NAME,
            temperature: attempt.zero? ? 0.3 : 0
          )
        rescue Allure::Assistant::Client::MalformedResponseError => error
          Rails.error.report(error, handled: true, context: { component: self.class.name })
          next
        end
        calls += result.calls
        model = result.model
        answer = parse(result.content)
        verified = answer && verifier.call(answer)
        break if verified&.valid?
      end
      Outcome.new(verified:, model:, calls:)
    end

    # The refused sentences are shown to the model, never logged.
    def retry_user(prompt, verified)
      refused = Array(verified&.refused_sentences).first(5)
      return prompt.user if refused.empty?

      lines = refused.map do |row|
        "- #{row["text"].to_s.truncate(200)} (cites: #{Array(row["fact_ids"]).join(", ")})"
      end
      <<~TEXT
        #{prompt.user}

        Your previous answer was refused: these sentences cite facts that do not carry their numbers.
        #{lines.join("\n")}
        Rewrite the whole summary. Every number must appear in the facts you cite; cite the fact that carries it.
      TEXT
    end

    # The schema is enforced by the provider where it can be; a prompt-only
    # answer may fence its JSON.
    def parse(content)
      text = content.to_s.strip
      JSON.parse(text)
    rescue JSON::ParserError
      fenced = text[/```(?:json)?\s*(.+?)```/m, 1] || text[/\{.*\}/m]
      return unless fenced

      begin
        JSON.parse(fenced)
      rescue JSON::ParserError
        nil
      end
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
