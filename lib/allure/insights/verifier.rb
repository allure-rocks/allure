# frozen_string_literal: true

module Allure
  module Insights
    # What may be shown from a model answer (docs/dev/AI.md §4.4): each sentence
    # must cite known facts, and every number it writes must come from one of
    # them. The verifier never rewrites; it drops.
    class Verifier
      MAX_TITLE = 60

      Result = Data.define(:title, :sentences, :refused_fact_ids, :refused_sentences) do
        def valid? = sentences.size >= 2
        def dropped? = refused_sentences.any?
      end

      def initialize(facts)
        @facts = facts.to_h { |fact| [ fact.id, fact ] }
        @numbers = @facts.transform_values { |fact| digits(fact.display) }
      end

      def call(answer)
        return Result.new(title: nil, sentences: [], refused_fact_ids: [], refused_sentences: []) unless answer.is_a?(Hash)

        sentences, refused_ids, refused_sentences = accepted_sentences(answer["sentences"])
        Result.new(title: accepted_title(answer["title"]), sentences:, refused_fact_ids: refused_ids,
                   refused_sentences:)
      end

      private

      attr_reader :facts, :numbers

      def accepted_sentences(rows)
        kept = []
        refused_ids = []
        refused_sentences = []
        Array(rows).each do |row|
          next unless row.is_a?(Hash)

          text = row["text"].to_s.strip
          ids = Array(row["fact_ids"]).map(&:to_s)
          if text.empty? || ids.empty? || ids.any? { !facts.key?(it) } || !covered?(text, ids)
            refused_ids.concat(ids)
            refused_sentences << { "text" => text, "fact_ids" => ids } unless text.empty?
            next
          end

          kept << { "text" => text, "fact_ids" => ids }
        end
        [ kept, refused_ids.uniq, refused_sentences ]
      end

      def covered?(text, ids)
        allowed = ids.flat_map { numbers.fetch(it, []) }
        digits(text).all? { allowed.include?(it) }
      end

      # The title cites nothing, so it may only use numbers present somewhere in
      # the facts.
      def accepted_title(title)
        text = title.to_s.strip
        return if text.empty? || text.length > MAX_TITLE

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
