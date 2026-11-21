# frozen_string_literal: true

module Workouts
  # A generation and its verification retry, independent of the summary row.
  class SummaryGeneration
    # Warmer than a data extraction: the verifier, not the temperature, guards
    # the numbers (AI.md §2), and a little warmth keeps the wording from
    # settling into one formula.
    TEMPERATURE = 0.7
    Outcome = Data.define(:verified, :model, :calls, :prompt_tokens, :completion_tokens, :reasoning)

    # `capture_reasoning` is for the local blind comparison only (AI.md §11);
    # the job never asks for it, so nothing of it is ever stored.
    def call(snapshot, prompt: nil, client: Allure::Assistant::Config.client, temperature: TEMPERATURE,
             capture_reasoning: false)
      prompt ||= Allure::Insights::Prompt.new(facts: snapshot.facts, locale: snapshot.locale,
                                              sport: snapshot.sport_slug)
      verifier = Allure::Insights::Verifier.new(snapshot.facts, max_sentences: prompt.max_sentences)
      calls = prompt_tokens = completion_tokens = 0
      model = verified = reasoning = nil
      2.times do |attempt|
        begin
          result = client.complete(system: prompt.system, user: attempt.zero? ? prompt.user : retry_user(prompt, verified),
                                   schema: schema_for(client, prompt),
                                   schema_name: Allure::Insights::Prompt::SCHEMA_NAME,
                                   temperature: attempt.zero? ? temperature : 0,
                                   capture_reasoning: capture_reasoning)
        rescue Allure::Assistant::Client::MalformedResponseError => error
          Rails.error.report(error, handled: true, context: { component: self.class.name })
          yield(nil) if block_given?
          next
        end
        calls += result.calls
        model = result.model
        prompt_tokens += result.prompt_tokens
        completion_tokens += result.completion_tokens
        reasoning = result.reasoning.presence || reasoning
        answer = parse(result.content)
        verified = answer && verifier.call(answer)
        yield(verified) if block_given?
        break if verified&.valid?
      end
      Outcome.new(verified:, model:, calls:, prompt_tokens:, completion_tokens:, reasoning:)
    end

    private

    # The reference engine returns its answer in `reasoning_content` — an
    # empty `content` — when a thinking mode and `response_format` meet, so a
    # reasoning client gets the shape in the prompt instead (AI.md §2).
    def schema_for(client, prompt)
      return if client.reasoning?

      Allure::Insights::SummarySchema.call(max_sentences: prompt.max_sentences)
    end

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
        Rewrite the whole summary with at least one sentence. Every number must appear in the facts you cite;
        cite the fact that carries it.
      TEXT
    end

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
  end
end
