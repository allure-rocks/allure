# frozen_string_literal: true

module DevTools
  # The production prompt as it stood before the free-selection rewrite
  # (2026-11): a weight-sorted fact table, an imposed highlight, three style
  # examples and a fixed jargon list. Kept only so `dev_tools:insights_compare`
  # can measure the rewrite against it; never used to write a stored summary.
  class LegacySummaryPrompt
    SCHEMA_NAME = "workout_summary"
    NOTABLE_WEIGHT = 70
    LANGUAGES = { fr: "French", en: "English", de: "German", es: "Spanish", nl: "Dutch" }.freeze
    ADDRESS = { fr: "vous", en: "you", de: "du", es: "tú", nl: "je" }.freeze
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
    JARGON = {
      "cycling" => %w[D+ bosse col enrouler mouliner avaler relance],
      "running" => %w[D+ footing fractionné côte relance],
      "hiking" => %w[D+ crapahuter sentier grimpette sommet],
      "skiing" => %w[D+ peaux poudre piste descente],
      "swimming" => %w[longueurs bassin crawl virage coulée]
    }.freeze
    FAMILIES = {
      "cycling" => %w[cycling cycling_road cycling_gravel cycling_electric cycling_trekking
                      cycling_virtual mountain_biking mountain_biking_electric],
      "running" => %w[running running_virtual trail],
      "hiking" => %w[walking hiking mountaineering snowshoes],
      "skiing" => %w[skiing_alpine skiing_touring skiing_cross_country snowboarding],
      "swimming" => %w[pool_swimming open_water_swimming swimrun]
    }.freeze

    attr_reader :sentence_range

    def initialize(facts:, locale:, sport: nil, sentence_range: nil)
      @facts = facts
      @locale = locale.to_sym
      @sport = sport
      @sentence_range = sentence_range || self.class.sentence_range(facts)
    end

    def max_sentences = sentence_range.max

    def self.sentence_range(facts)
      case notable(facts).size
      when 0, 1 then 1..1
      when 2 then 1..2
      when 3..4 then 2..3
      else 3..5
      end
    end

    def self.notable(facts)
      facts.reject { it.kind == "baseline" || it.kind == "section" }
           .select { it.weight >= NOTABLE_WEIGHT && it.sentiment.to_s != "neutral" }
    end

    def self.highlight(facts)
      facts.reject { it.kind == "baseline" || it.kind == "section" }
           .min_by { |item| [ item.sentiment.to_s != "neutral" ? 0 : 1, -item.weight,
                              Allure::Insights::Facts::KINDS.index(item.kind), item.id ] }
    end

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

    def jargon_line
      family = FAMILIES.find { |_name, slugs| slugs.include?(sport.to_s) }&.first
      return nil unless family

      words = JARGON.fetch(family, nil)
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
      item = self.class.highlight(facts)
      return "" unless item

      "Highlight this fact: #{item.id} — #{item.display}\n"
    end

    def fact_display(id) = facts.find { it.id == id }&.display

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
