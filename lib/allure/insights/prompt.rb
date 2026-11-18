# frozen_string_literal: true

module Allure
  module Insights
    # The instructions and the facts table (docs/dev/AI.md §4.1–§4.2): English
    # in, the member's language out. The model only phrases the facts; the
    # verifier refuses anything else.
    class Prompt
      SCHEMA_NAME = "workout_summary"
      LANGUAGES = { fr: "French", en: "English", de: "German", es: "Spanish", nl: "Dutch" }.freeze
      # The DESIGN.md §4 glossary, reduced to the words a summary uses.
      GLOSSARY = {
        fr: { "workout" => "activité", "personal best" => "record", "ascent" => "dénivelé",
              "pace" => "allure", "speed" => "vitesse", "lap" => "tour" },
        en: { "workout" => "workout", "personal best" => "personal best", "ascent" => "ascent",
              "pace" => "pace", "speed" => "speed", "lap" => "lap" },
        de: { "workout" => "Aktivität", "personal best" => "Rekord", "ascent" => "Höhenmeter",
              "pace" => "Pace", "speed" => "Geschwindigkeit", "lap" => "Runde" },
        es: { "workout" => "actividad", "personal best" => "récord", "ascent" => "desnivel",
              "pace" => "ritmo", "speed" => "velocidad", "lap" => "vuelta" },
        nl: { "workout" => "activiteit", "personal best" => "record", "ascent" => "hoogtemeters",
              "pace" => "tempo", "speed" => "snelheid", "lap" => "ronde" }
      }.freeze

      def initialize(facts:, locale:)
        @facts = facts
        @locale = locale.to_sym
      end

      def system
        <<~TEXT
          You are the assistant of a self-hosted Allure instance. You write the summary of one workout for its owner, in #{language}.

          Rules:
          - Use only the facts below. Never invent a number, a place, a person, a time or a comparison.
          - Every sentence cites at least one fact id in its "fact_ids" field. Never write a fact id in the text.
          - Two to five sentences. Sober register, second person. No exclamation, no emoji, no training advice that a fact does not support.
          - Write every number in digits, exactly as its fact writes it. Prefer the facts' own words for numbers, units and temperatures.
          - The title is a short name for this outing, at most 60 characters, that uses only numbers from the facts. Never propose the sport and the date alone, as an import does.

          Terminology in #{language}: #{glossary}.

          Answer only with the JSON object described by the schema.
        TEXT
      end

      def user
        <<~TEXT
          #{context_line}

          Facts (id | display | sentiment):
          #{fact_lines}
        TEXT
      end

      def messages = [ { role: "system", content: system }, { role: "user", content: user } ]

      private

      attr_reader :facts, :locale

      def language = LANGUAGES.fetch(locale, "English")

      def glossary = GLOSSARY.fetch(locale, GLOSSARY[:en]).map { |english, word| "#{english} = #{word}" }.join("; ")

      def context_line
        sport = fact_display("baseline:sport")
        date = fact_display("baseline:date")
        [ ("Sport: #{sport}" if sport), ("Date: #{date}" if date) ].compact.join(". ")
      end

      def fact_display(id) = facts.find { it.id == id }&.display

      def fact_lines
        facts.map { |fact| "#{fact.id} | #{fact.display} | #{fact.sentiment}" }.join("\n")
      end
    end
  end
end
