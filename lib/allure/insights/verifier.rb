# frozen_string_literal: true

module Allure
  module Insights
    # What may be shown from a model answer (docs/dev/AI.md §4.4): each sentence
    # must cite known facts, and every number it writes must come from one of
    # them. The verifier never rewrites; it drops, and keeps at most the number
    # of sentences the prompt asked for.
    class Verifier
      MAX_TITLE = 60
      MAX_SENTENCES = SummarySchema::MAX_SENTENCES

      Result = Data.define(:title, :sentences, :refused_fact_ids, :refused_sentences) do
        # One verified sentence is a complete answer: a quiet outing says one
        # sentence and stops (AI.md §4.1).
        def valid? = sentences.size >= 1
        def dropped? = refused_sentences.any?
      end

      def initialize(facts, max_sentences: MAX_SENTENCES)
        @facts = facts.to_h { |fact| [ fact.id, fact ] }
        @fact_ids = @facts.keys
        @numbers = @facts.transform_values { |fact| digits(fact.display) }
        @max_sentences = max_sentences.clamp(1, MAX_SENTENCES)
      end

      def call(answer)
        return Result.new(title: nil, sentences: [], refused_fact_ids: [], refused_sentences: []) unless answer.is_a?(Hash)

        sentences, refused_ids, refused_sentences = accepted_sentences(answer["sentences"])
        Result.new(title: accepted_title(answer["title"]), sentences:, refused_fact_ids: refused_ids,
                   refused_sentences:)
      end

      private

      attr_reader :facts, :fact_ids, :numbers, :max_sentences

      def accepted_sentences(rows)
        kept = []
        refused_ids = []
        refused_sentences = []
        Array(rows).each do |row|
          next unless row.is_a?(Hash)

          text = row["text"].to_s.strip
          ids = Array(row["fact_ids"]).map(&:to_s)
          if text.empty? || ids.empty? || ids.any? { !facts.key?(it) } || !covered?(text, ids) || leaked_id?(text)
            refused_ids.concat(ids)
            refused_sentences << { "text" => text, "fact_ids" => ids } unless text.empty?
            next
          end

          kept << { "text" => text, "fact_ids" => ids }
        end
        [ kept.first(max_sentences), refused_ids.uniq, refused_sentences ]
      end

      def covered?(text, ids)
        allowed = ids.flat_map { numbers.fetch(it, []) }
        digits(text).all? { allowed.include?(it) }
      end

      # The prompt forbids writing a fact id in the text; a small model slips
      # (« La montée de section:4 … »), and an internal id must never reach the
      # member. An id is data for the machine, not prose.
      def leaked_id?(text)
        downcased = text.downcase
        fact_ids.any? { |id| downcased.include?(id.downcase) }
      end

      # The title cites nothing, so it may only use numbers present somewhere in
      # the facts.
      def accepted_title(title)
        text = title.to_s.strip
        return if text.empty? || text.length > MAX_TITLE || leaked_id?(text)

        allowed = numbers.values.flatten
        return unless digits(text).all? { allowed.include?(it) }

        text
      end

      # Digits only: « 2 068 m », « 2'068 », « 2 068 » and « 2068 » are one
      # number; a decimal comma or point is ignored, and so are units and °.
      def digits(text) = text.to_s.gsub(/[[:space:]'’]/, "").scan(/\d+/)
    end
  end
end
