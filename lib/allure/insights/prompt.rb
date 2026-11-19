# frozen_string_literal: true

module Allure
  module Insights
    # The instructions and the facts table (docs/dev/AI.md §4.1–§4.2): English
    # in, the member's language out. The model only phrases the facts; the
    # verifier refuses anything else.
    #
    # The voice is DESIGN.md §3.1 — a knowledgeable friend, direct and a little
    # wry — never the sober register of the privacy copy. The style examples are
    # fictional and say so: a small model copies what it is shown.
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
      # Two answers per language: a rich outing and a quiet one. They show the
      # rhythm, not the content: the places are plainly made up, so a small
      # model has nothing real to copy, and the quiet one is worded differently
      # from the phrasing the prompt suggests.
      STYLE_EXAMPLES = {
        fr: [
          "Faits « montée de 5,6 km à 6 %, effort régulier » → « La montée de 5,6 km a pris son temps, " \
          "mais l'allure à plat, elle, n'a pas bougé. » Titre : « La montée sans à-coup ».",
          "Faits sans rien de marquant → « Une heure de vélo sans surprise, et c'est très bien comme ça. » " \
          "Titre : « Boucle tranquille »."
        ],
        en: [
          "Facts “a 5.6 km climb at 6%, even effort” → “The 5.6 km climb took its time, but the " \
          "flat-equivalent pace never moved. Steady all the way up.” Title: “Steady on the climb”.",
          "No fact worth a story → “An hour on the bike, no surprises, and that is perfectly fine.” " \
          "Title: “A quiet loop”."
        ],
        de: [
          "Fakten „5,6 km Anstieg bei 6 %, gleichmäßiger Aufwand“ → „Der Anstieg über 5,6 km hat Zeit " \
          "gebraucht, aber das flache Tempo blieb, wo es war.“ Titel: „Gleichmäßig am Anstieg“.",
          "Keine erwähnenswerte Tatsache → „Eine Stunde auf dem Rad, ohne Überraschung, und das ist völlig in " \
          "Ordnung.“ Titel: „Ruhige Runde“."
        ],
        es: [
          "Hechos «subida de 5,6 km al 6 %, esfuerzo regular» → «La subida de 5,6 km se tomó su tiempo, " \
          "pero el ritmo en llano no se movió.» Título: «Subida sin sobresaltos».",
          "Ningún hecho que merezca una historia → «Una hora de bici sin sorpresas, y así está perfecto.» " \
          "Título: «Vuelta tranquila»."
        ],
        nl: [
          "Feiten ‘klim van 5,6 km aan 6 %, gelijkmatige inspanning’ → ‘De klim van 5,6 km kostte tijd, " \
          "maar het vlakke tempo bleef waar het was.’ Titel: ‘Gelijkmatig de klim op’.",
          "Geen feit dat een verhaal verdient → ‘Een uur op de fiets, zonder verrassingen, en dat is prima.’ " \
          "Titel: ‘Rustig rondje’."
        ]
      }.freeze

      attr_reader :sentence_range

      def initialize(facts:, locale:, sentence_range: nil)
        @facts = facts
        @locale = locale.to_sym
        @sentence_range = sentence_range || Facts.sentence_range(facts)
      end

      def max_sentences = sentence_range.max

      def system
        <<~TEXT
          You are the assistant of a self-hosted Allure instance. You write the summary of one workout for its owner, in #{language}.

          Voice:
          - Write like a knowledgeable friend who respects their time: direct, concrete, a little wry. Personality lives in word choice and rhythm, never in volume.
          - Second person. No exclamation mark, no emoji, no forced congratulation, no motivational slogan.
          - Stay kind: a hard day is told plainly, never as a reproach, and never with training advice a fact does not support.
          - The course table describes the route in order. Use it to tell the shape of the outing: where it climbed, where the pace was easy or hard, how it ended. Never walk through the sections one by one; pick the one or two that carry the story. A slow section that climbs is the road, not a verdict on the effort. Never claim fatigue, loss or a constant effort unless a course fact says it. Cite the section ids you use.
          - Open with the highlighted fact and build one short story around it. Do not list the facts. Restate the distance, the time or the ascent only when they serve that story. When nothing is notable, one quiet sentence is the right answer: do not inflate it.

          Rules:
          - Use only the facts below. Never invent a number, a place, a person, a time or a comparison.
          - You may name a place that a fact carries, to set the scene, but never a place it does not carry.
          - Every sentence cites at least one fact id in its "fact_ids" field. Never write a fact id in the text.
          - #{sentence_instruction}
          - Write every number in digits, exactly as its fact writes it. Prefer the facts' own words for numbers, units and temperatures.
          - The title is a short name for this outing, at most 60 characters, that uses only numbers from the facts. A place from the facts makes a good title. Never propose the sport and the date alone, as an import does.

          Terminology in #{language}: #{glossary}.

          Style examples (fictional facts, for tone only: never reuse their places, numbers, wording or sentences):
          #{examples}

          Answer only with the JSON object described by the schema.
        TEXT
      end

      def user
        <<~TEXT
          #{context_line}
          #{user_sentence_line}
          #{highlight_line}
          Facts (id | display | sentiment):
          #{fact_lines}
          #{course_block}
        TEXT
      end

      def messages = [ { role: "system", content: system }, { role: "user", content: user } ]

      private

      attr_reader :facts, :locale

      def language = LANGUAGES.fetch(locale, "English")

      def glossary = GLOSSARY.fetch(locale, GLOSSARY[:en]).map { |english, word| "#{english} = #{word}" }.join("; ")

      def examples = STYLE_EXAMPLES.fetch(locale, STYLE_EXAMPLES[:en]).join("\n")

      def sentence_instruction
        return "Write exactly one sentence." if sentence_range.max == 1

        "Write between #{sentence_range.min} and #{sentence_range.max} sentences."
      end

      def user_sentence_line
        return "Sentences: exactly 1." if sentence_range.max == 1

        "Sentences: #{sentence_range.min} to #{sentence_range.max}."
      end

      def context_line
        sport = fact_display("baseline:sport")
        date = fact_display("baseline:date")
        [ ("Sport: #{sport}" if sport), ("Date: #{date}" if date) ].compact.join(". ")
      end

      def highlight_line
        item = Facts.highlight(facts)
        return "" unless item

        "Highlight this fact: #{item.id} — #{item.display}\n"
      end

      def fact_display(id) = facts.find { it.id == id }&.display

      # The route's sections travel apart: they describe the course, they never
      # compete with the facts for the summary's angle (AI.md §4.2).
      def fact_lines
        facts.reject { it.kind == "section" }
             .map { |fact| "#{fact.id} | #{fact.display} | #{fact.sentiment}" }
             .join("\n")
      end

      def course_block
        sections = facts.select { it.kind == "section" }
        return "" if sections.empty?

        "Course, in order from the start (id | section):\n" +
          sections.map { |section| "#{section.id} | #{section.display}" }.join("\n")
      end
    end
  end
end
