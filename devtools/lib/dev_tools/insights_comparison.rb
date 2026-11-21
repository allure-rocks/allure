# frozen_string_literal: true

require "json"
require "tmpdir"
require_relative "legacy_summary_prompt"

module DevTools
  # A blind A/B reading of two summary prompts on the same snapshot
  # (docs/dev/AI.md §11). The reference side is always the production prompt;
  # the candidate side is either the previous prompt (`PROMPT=legacy`, the
  # default) or the same production prompt with provider options such as
  # reasoning (`PROMPT=reference`, plus `OPTIONS`).
  #
  # The two series are shuffled into pairs.txt; diagnostics.txt names the
  # variants, shows the prompt, the timing, the reasoning when it was captured,
  # and diversity.txt counts what the summaries repeat.
  class InsightsComparison
    class DirectedPrompt < Allure::Insights::Prompt
      attr_accessor :direction

      private

      def story_lines
        lines = super
        direction.present? ? lines + [ "- Editorial direction for this test: #{direction}" ] : lines
      end
    end

    MODES = %w[legacy reference].freeze

    def initialize(workouts:, env: ENV)
      @workouts = workouts
      @config = Allure::Assistant::Config
      @model = env.fetch("MODEL", @config.model)
      @mode = env.fetch("PROMPT", "legacy")
      raise ArgumentError, "PROMPT: legacy or reference" unless MODES.include?(@mode)
      @direction = env["DIRECTION"].presence
      @options = @config.request_options.dup
      @options.merge!(candidate_options(env["OPTIONS"])) if env["OPTIONS"].present?
      @options["temperature"] = Float(env["TEMP"]) if env["TEMP"]
      @options["max_tokens"] = Integer(env["TOKENS"]) if env["TOKENS"]
    end

    def call
      variants = %i[reference candidate].shuffle
      series = [ [], [] ]
      pairs = []
      diagnostics = []
      rows = []
      @workouts.each do |workout|
        snapshot = Workouts::SummaryFacts.new(workout).call
        label = "#{workout.to_param} · #{workout.title}"
        pairs << label
        variants.each_with_index do |variant, index|
          reason = Workouts::SummaryEligibility.reason(workout.reload)
          raise ArgumentError, "Workout ineligible: #{reason}" if reason
          letter = %w[A B].fetch(index)
          text, details, answer = generate(snapshot, workout, variant)
          series[index] << "#{label}\n#{text}"
          pairs << "#{letter}: #{text}"
          diagnostics << "#{label} · #{letter} (#{variant})\n#{details}"
          rows << { label:, letter:, variant:, snapshot:, answer: }
        end
        pairs << "Vote: A / B / equivalent / neither\n\n"
      end
      dir = Dir.mktmpdir("insights-", Rails.root.join("tmp"))
      files = {
        "pairs" => pairs.join("\n"), "diagnostics" => diagnostics.join("\n\n"),
        "diversity" => diversity(rows)
      }
      series.each_with_index { |items, i| files["series-#{%w[A B][i]}"] = items.join("\n\n") }
      files.each { |name, text| File.write(File.join(dir, "#{name}.txt"), text) }
      dir
    end

    private

    def candidate_options(raw)
      parsed = JSON.parse(raw)
      raise ArgumentError, "OPTIONS must be a JSON object" unless parsed.is_a?(Hash)

      parsed
    rescue JSON::ParserError => error
      raise ArgumentError, "OPTIONS is not JSON: #{error.message}"
    end

    def generate(snapshot, workout, variant)
      candidate = variant == :candidate
      prompt = prompt_for(snapshot, workout, candidate)
      options = candidate ? @options : @config.request_options
      model = candidate ? @model : @config.model
      client = Allure::Assistant::Client.new(base_url: @config.base_url, model:, api_key: @config.api_key,
                                             timeout: @config.timeout, request_options: options)
      details = [ "Model: #{model}; temperature: #{options.fetch('temperature', Workouts::SummaryGeneration::TEMPERATURE)}; " \
                  "max_tokens: #{options.fetch('max_tokens', Allure::Assistant::Client::MAX_TOKENS)}; " \
                  "reasoning: #{options.fetch('reasoning_effort', 'default')}",
                  prompt.system, prompt.user ]
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      outcome = Workouts::SummaryGeneration.new.call(snapshot, prompt:, client:, capture_reasoning: candidate) do |verified|
        details << (verified ? "Refused: #{verified.refused_sentences.to_json}" : "Invalid response")
      end
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      rows = Array(outcome.verified&.sentences)
      details << "Returned model: #{outcome.model}; elapsed: #{format('%.1f', elapsed)} s; accepted: #{rows.to_json}"
      details << "Reasoning (not stored):\n#{outcome.reasoning}" if outcome.reasoning.present?
      answer = {
        title: outcome.verified&.title, text: rows.pluck("text").join(" "), sentences: rows.size,
        fact_ids: rows.flat_map { it["fact_ids"] }, elapsed:
      }
      [ answer[:text].presence || "[No verified summary]", details.join("\n"), answer ]
    rescue Allure::Assistant::Client::Error => error
      [ "[Generation failed]", (Array(details) + [ error.class.name, error.message ]).join("\n"), nil ]
    end

    def prompt_for(snapshot, workout, candidate)
      if candidate && @mode == "legacy"
        LegacySummaryPrompt.new(facts: snapshot.facts, locale: snapshot.locale, sport: workout.sport.slug)
      elsif candidate
        DirectedPrompt.new(facts: snapshot.facts, locale: snapshot.locale, sport: workout.sport.slug)
                      .tap { it.direction = @direction }
      else
        Allure::Insights::Prompt.new(facts: snapshot.facts, locale: snapshot.locale, sport: workout.sport.slug)
      end
    end

    # What the two series repeat (docs/dev/AI.md §11): the opening, the
    # records, the expressions, and whether a fact the page does not show —
    # company, weather, place — was used when it existed.
    def diversity(rows)
      rows.group_by { it[:variant] }.map do |variant, items|
        items = items.reject { it[:answer].nil? }
        next "#{variant}: no verified answer" if items.empty?

        lines = [ "== #{variant} (#{items.size} answers)" ]
        lines << "starts with a number: #{items.count { digits_first?(it[:answer][:text]) }}/#{items.size}"
        lines << "mentions a record: #{items.count { record?(it[:answer][:text]) || record?(it[:answer][:title]) }}/#{items.size}"
        lines << "average sentences: #{average(items.map { it[:answer][:sentences] }).round(1)}"
        lines << "average words per sentence: #{average(items.map { words_per_sentence(it[:answer]) }).round(1)}"
        lines << "average generation time: #{average(items.map { it[:answer][:elapsed] }).round(1)} s"
        lines << "repeated 3-grams:"
        trigrams(items.flat_map { [ it[:answer][:text], it[:answer][:title] ] }).each do |gram, count|
          lines << "  #{count}× #{gram}"
        end
        lines << "fact kinds cited: #{kind_counts(items).join(', ')}"
        lines.concat(unshown_coverage(items))
        lines.join("\n")
      end.join("\n\n") + "\n"
    end

    def digits_first?(text) = text.to_s.lstrip.match?(/\A[−-]?\d/)
    def record?(text) = text.to_s.match?(/record|rekord|récord/i)

    def average(values)
      return 0.0 if values.empty?

      values.sum.to_f / values.size
    end

    def words_per_sentence(answer)
      return 0.0 if answer[:sentences].to_i.zero?

      answer[:text].split.size.to_f / answer[:sentences]
    end

    def trigrams(texts)
      texts.compact.flat_map { |text| text.to_s.downcase.scan(/[\p{L}\p{N}'’-]+/) }
           .each_cons(3).map { |gram| gram.join(" ") }
           .tally.sort_by { |gram, count| [ -count, gram ] }.first(10)
    end

    def kind_counts(items)
      kinds = items.flat_map { it[:answer][:fact_ids] }
                   .to_h { |id| [ id, id.split(":").first ] }
      items.flat_map { it[:answer][:fact_ids] }.filter_map { kinds[it] }
           .tally.sort_by { |kind, count| [ -count, kind ] }.map { |kind, count| "#{kind} #{count}" }
    end

    # For the facts the page does not show, how often a summary used one when
    # its snapshot carried it.
    def unshown_coverage(items)
      %w[company weather place].filter_map do |kind|
        concerned = items.select { it[:snapshot].facts.any? { |fact| fact.kind == kind } }
        next if concerned.empty?

        used = concerned.count do |item|
          ids = item[:snapshot].facts.select { |fact| fact.kind == kind }.map(&:id)
          (item[:answer][:fact_ids] & ids).any?
        end
        "#{kind} cited when available: #{used}/#{concerned.size}"
      end
    end
  end
end
