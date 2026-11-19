# frozen_string_literal: true

module Allure
  module Insights
    # The instructions and the facts table (docs/dev/AI.md §4.1–§4.2): English
    # in, the member's language out. The model only phrases the facts; the
    # verifier refuses anything else.
    #
    # The voice is DESIGN.md §3.1–§3.2: a training partner texting right after
    # the outing, not the sober register. A summary may borrow the sport's
    # jargon (DESIGN.md §4) and close a personal best with one exclamation
    # mark, never an emoji. The style examples are fictional and say so: a
    # small model copies what it is shown.
    class Prompt
      SCHEMA_NAME = "workout_summary"
      LANGUAGES = { fr: "French", en: "English", de: "German", es: "Spanish", nl: "Dutch" }.freeze
      # The address form of DESIGN.md §3.4 and §3.4b, spelled out so a small
      # model never has to choose one: French vouvoie, the other languages
      # tutoient.
      ADDRESS = { fr: "vous", en: "you", de: "du", es: "tú", nl: "je" }.freeze
      # The administrative verbs and hollow turns that turn a summary into a
      # press release. "A little wry" alone gave a small model nothing to hold
      # on to; these are the exact words to leave out, in its own language.
      AVOID = {
        fr: "inscrit, inscrits, fixe, fixent, établi, établie, offert, offerte, affiche, enregistre, " \
            "s'élève à, constitue, « a pris son temps », « force est de constater », « à noter que », " \
            "« sans à-coup »",
        en: "registered, recorded, established, offered, boasted, clocked in at, constituted, " \
            "“took its time”, “it is worth noting”",
        de: "verzeichnet, weist auf, beläuft sich auf, bietet, festgehalten, " \
            "„hat sich Zeit gelassen“, „es ist anzumerken“",
        es: "registró, estableció, ofreció, contabilizó, «se tomó su tiempo», " \
            "«cabe destacar», «se situó en»",
        nl: "noteerde, legde vast, bood, bedroeg, opgetekend, ‘het kostte tijd’, " \
            "‘het is opmerkelijk’"
      }.freeze
      # The DESIGN.md §4 glossary, reduced to the words a summary uses. The
      # sport's jargon may replace these; a unit never.
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
      # Three answers per language: a rich outing, a personal best and a quiet
      # one. They show the rhythm, not the content: the places are plainly made
      # up, so a small model has nothing real to copy, and the quiet one is
      # worded differently from the phrasing the prompt suggests. Every number
      # they print is one their fictional fact carries, exactly as the verifier
      # would demand of a real answer.
      STYLE_EXAMPLES = {
        fr: [
          "Faits « montée de 5,6 km à 6 %, effort régulier » → « 5,6 km de bosse à 6 %, et l'allure " \
          "n'a pas bougé d'un poil. Du travail propre. » Titre : « Métronome dans la bosse ».",
          "Faits « 142,3 km, plus longue distance à ce jour » → « 142,3 km : vous n'aviez jamais roulé " \
          "aussi loin ! » Titre : « La plus grosse sortie ».",
          "Faits sans rien de marquant → « Une heure à enrouler, rien à signaler. Parfois, c'est exactement " \
          "ce qu'il faut. » Titre : « Boucle pépère »."
        ],
        en: [
          "Facts “a 5.6 km climb at 6%, even effort” → “5.6 km of climbing at 6%, and the pace never " \
          "budged. Tidy work.” Title: “Metronome on the climb”.",
          "Facts “142.3 km, longest distance yet” → “142.3 km. You have never ridden this far!” " \
          "Title: “The big one”.",
          "No fact worth a story → “An hour of easy spinning, nothing to report. Some days that is " \
          "exactly right.” Title: “Easy loop”."
        ],
        de: [
          "Fakten „5,6 km Anstieg bei 6 %, gleichmäßiger Aufwand“ → „5,6 km Anstieg mit 6 %, und dein " \
          "Tempo hat sich keinen Millimeter bewegt. Sauber.“ Titel: „Metronom am Berg“.",
          "Fakten „142,3 km, längste Distanz bisher“ → „142,3 km: So weit bist du noch nie gefahren!“ " \
          "Titel: „Die große Runde“.",
          "Keine erwähnenswerte Tatsache → „Eine Stunde locker gekurbelt, nichts Besonderes. Manchmal " \
          "genau richtig.“ Titel: „Lockere Runde“."
        ],
        es: [
          "Hechos «subida de 5,6 km al 6 %, esfuerzo regular» → «5,6 km de subida al 6 %, y el ritmo ni " \
          "se inmutó. Trabajo limpio.» Título: «Metrónomo en la subida».",
          "Hechos «142,3 km, la distancia más larga hasta ahora» → «142,3 km: ¡nunca habías rodado tan " \
          "lejos!» Título: «La salida más larga».",
          "Ningún hecho que merezca una historia → «Una hora rodando suave, nada que contar. A veces es " \
          "justo lo que toca.» Título: «Vuelta tranquila»."
        ],
        nl: [
          "Feiten ‘klim van 5,6 km aan 6 %, gelijkmatige inspanning’ → ‘5,6 km klimmen aan 6 %, en je " \
          "tempo gaf geen krimp. Netjes.’ Titel: ‘Metronoom op de klim’.",
          "Feiten ‘142,3 km, langste afstand tot nu toe’ → ‘142,3 km: zo ver heb je nog nooit gefietst!’ " \
          "Titel: ‘De grote tocht’.",
          "Geen feit dat een verhaal verdient → ‘Een uur rustig doortrappen, niks bijzonders. Soms is dat " \
          "precies goed.’ Titel: ‘Rustig rondje’."
        ]
      }.freeze

      attr_reader :sentence_range

      def initialize(facts:, locale:, sport: nil, sentence_range: nil)
        @facts = facts
        @locale = locale.to_sym
        @sport = sport
        @sentence_range = sentence_range || Facts.sentence_range(facts)
      end

      def max_sentences = sentence_range.max

      def system
        [
          "You are the assistant of a self-hosted Allure instance. You write the summary of one workout " \
          "for its owner, in #{language}.",
          "",
          "Voice:",
          *voice_lines,
          "",
          "Rules:",
          "- Use only the facts below. Never invent a number, a place, a person, a time or a comparison.",
          "- You may name a place that a fact carries, to set the scene, but never a place it does not carry.",
          "- Every sentence cites at least one fact id in its \"fact_ids\" field. Never write a fact id in the text.",
          "- #{sentence_instruction}",
          "- Write every number in digits with its unit, exactly as its fact writes them. Jargon may replace " \
          "a word, never a unit. Rephrase the fact labels freely: they are data, not prose.",
          "- The title is a punchy nickname for this outing: 2 to 6 words, at most 60 characters, and the " \
          "sport's jargon is welcome. It uses only numbers the facts carry, and a place from the facts makes " \
          "a good one. Never the sport and the date alone, the way an import names a file.",
          "",
          "Terminology in #{language}: #{glossary}. The sport words above may replace these in a sentence.",
          "",
          "Style examples (fictional facts, for tone only: never reuse their places, numbers, wording or sentences):",
          examples,
          "",
          "Answer only with the JSON object described by the schema."
        ].join("\n") + "\n"
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

      attr_reader :facts, :locale, :sport

      def language = LANGUAGES.fetch(locale, "English")

      def address = ADDRESS.fetch(locale, ADDRESS[:en])

      def avoid = AVOID.fetch(locale, AVOID[:en])

      def glossary = GLOSSARY.fetch(locale, GLOSSARY[:en]).map { |english, word| "#{english} = #{word}" }.join("; ")

      def examples = STYLE_EXAMPLES.fetch(locale, STYLE_EXAMPLES[:en]).join("\n")

      def voice_lines
        [
          "- You are a training partner texting right after the outing: warm, direct, a bit cheeky. " \
          "Spoken language, never a report.",
          "- The athlete is the subject: \"you rode 204.6 km\", \"you climbed the last hill\", never " \
          "\"the 204.6 km set\" or \"the route offered\".",
          "- Use the everyday verbs of the sport, never administrative ones. Avoid in #{language}: #{avoid}.",
          "- Short sentences: at most 20 words, one idea each. Start with the number or the action, never " \
          "with a framing clause. At most one \"but\" in the whole summary.",
          jargon_line,
          "- Address the owner as \"#{address}\".",
          "- One exclamation mark at most, and only for a personal best or a first. No emoji, no " \
          "motivational slogan, no \"congratulations\".",
          "- Never restate the date or the sport name: the page already shows them.",
          "- Stay kind: a hard day is told plainly, never as a reproach, and never with training advice a " \
          "fact does not support.",
          "- The course table describes the route in order. Use it to tell the shape of the outing: where " \
          "it climbed, where the pace was easy or hard, how it ended. Never walk through the sections one " \
          "by one; pick the one or two that carry the story. A slow section that climbs is the road, not a " \
          "verdict on the effort. Never claim fatigue, loss or a constant effort unless a course fact says " \
          "it. Cite the section ids you use.",
          "- Open with the highlighted fact and build one short story around it. Do not list the facts. " \
          "Restate the distance, the time or the ascent only when they serve that story. When nothing is " \
          "notable, one quiet sentence is the right answer: do not inflate it."
        ].compact
      end

      # Only for a sport with a family (Allure::Insights::Jargon): a small model
      # with no word to hold on to writes in jargon anyway, and invents it.
      def jargon_line
        words = Jargon.words(sport, locale:)
        return nil unless words

        "- Talk the way people who do this sport talk: borrow a word or two of its jargon, never a " \
        "glossary — #{words.join(', ')}."
      end

      def sentence_instruction
        return "Write exactly one sentence." if sentence_range.max == 1

        "Write between #{sentence_range.min} and #{sentence_range.max} sentences."
      end

      def user_sentence_line
        return "Sentences: exactly 1." if sentence_range.max == 1

        "Sentences: #{sentence_range.min} to #{sentence_range.max}."
      end

      def context_line
        sport_name = fact_display("baseline:sport")
        date = fact_display("baseline:date")
        [ ("Sport: #{sport_name}" if sport_name), ("Date: #{date}" if date) ].compact.join(". ")
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
