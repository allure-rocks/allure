# frozen_string_literal: true

module Allure
  module Insights
    # The instructions and the facts table (docs/dev/AI.md §4.1–§4.2): English
    # in, the member's language out. The model only phrases the facts; the
    # verifier refuses anything else.
    #
    # The voice is DESIGN.md §3.1–§3.2: a training partner texting right after
    # the outing, not the sober register. The model chooses what the outing is
    # about — no fact is imposed, no angle is precomputed, and no style example
    # is shown: a small model copies what it is shown, and a shown example makes
    # every summary start the same way (AI.md §4.1). The register is described,
    # never modelled, and the sport's vocabulary is offered one word at a time.
    class Prompt
      SCHEMA_NAME = "workout_summary"
      # The answer's bound, not a target (AI.md §1, §4.1): one true sentence is
      # complete, three is a big day, and the prompt says so without turning
      # the bound into a length to fill.
      SENTENCES = 1..3
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
      # sport's own vocabulary may replace these; a unit never.
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
      # The figures the workout page already renders (DESIGN.md §10.26): the
      # model may restate them, but they are rarely the story (AI.md §4.2).
      SHOWN_KINDS = %w[baseline].freeze

      attr_reader :sentence_range

      def initialize(facts:, locale:, sport: nil, sentence_range: nil)
        @facts = facts
        @locale = locale.to_sym
        @sport = sport
        @sentence_range = sentence_range || SENTENCES
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
          "What to write:",
          *story_lines,
          "",
          "Rules:",
          "- Use only the facts below. Never invent a number, a place, a person, a time or a comparison.",
          "- You may name a place or a person a fact carries, to set the scene, but never one it does not carry.",
          "- Every sentence cites at least one fact id in its \"fact_ids\" field. Never write a fact id in the text.",
          "- #{sentence_instruction}",
          "- Write every number in digits with its unit, exactly as its fact writes them. A word may replace " \
          "another, never a unit. Rephrase the fact labels freely: they are data, not prose.",
          "- The title is a punchy nickname for this outing: 2 to 6 words, at most 60 characters. It uses only " \
          "numbers the facts carry, and a place, a person or a detail from the facts makes a good one. Never " \
          "the sport and the date alone, the way an import names a file.",
          "- Answer with one JSON object and nothing else: #{answer_shape}",
          "",
          "Terminology in #{language}: #{glossary}",
          "",
          "Answer only with that JSON object."
        ].join("\n") + "\n"
      end

      def user
        <<~TEXT
          #{context_line}
          #{user_sentence_line}
          #{fact_block}
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

      def voice_lines
        [
          "- You are a training partner texting right after the outing: warm, direct, a bit cheeky. " \
          "Spoken language, never a report.",
          "- The athlete is the subject, not the route or the data: say what you did, never what \"the " \
          "route offered\". A sentence may open on a place, the weather, a person or a detail before it " \
          "reaches you.",
          "- Use the everyday verbs of the sport, never administrative ones. Avoid in #{language}: #{avoid}.",
          "- Spoken rhythm: short sentences of uneven length, a fragment when it lands. At most 20 words " \
          "per sentence and at most one \"but\" in the whole summary. Link what belongs together; never " \
          "march through the facts one by one, and do not open two sentences the same way.",
          "- One warm or wry remark at most, and only when it is true of this outing: never a cliché, " \
          "never a slogan.",
          jargon_line,
          "- Address the owner as \"#{address}\".",
          "- One exclamation mark at most, and only for a personal best or a first. No emoji, no " \
          "motivational slogan, no \"congratulations\".",
          "- Never restate the date or the sport name: the page already shows them.",
          "- Stay kind: a hard day is told plainly, never as a reproach, and never with training advice a " \
          "fact does not support."
        ].compact
      end

      # The sport's vocabulary is an offer, not a glossary (AI.md §4.1): one
      # word at most, and most summaries take none. The climb words are only
      # listed when the outing climbed, so the prompt never invites a "col" on
      # a flat ride.
      def jargon_line
        words = Jargon.words(sport, locale:, climbing: climbed?)
        return nil unless words

        "- If one word of the sport's own vocabulary fits naturally, borrow it — #{words.join(', ')}. " \
        "Never a glossary, never a list of them, and most summaries need none."
      end

      def climbed? = facts.any? { it.kind == "climb" }

      # The model's freedom is the point (AI.md §3.4, §4.1): the code computes
      # and verifies, the model decides what the outing is about.
      def story_lines
        [
          "- Choose what this outing is about. One detail usually carries it: a climb, a place, the " \
          "weather, the people, the shape of the route, a number. Tell that one, and let the rest go.",
          "- The facts marked as already on the page are rarely worth repeating. The ones the page does " \
          "not show are often the story.",
          "- The course table describes the route in order. Use it to tell the shape of the outing: where " \
          "it climbed, where the pace was easy or hard, how it ended. Never walk through the sections one " \
          "by one; pick the one or two that carry the story. A slow section that climbs is the road, not a " \
          "verdict on the effort. Never claim fatigue, loss or a constant effort unless a course fact says " \
          "it. Cite the section ids you use.",
          "- Most outings need one or two sentences, three only for a big day. A quiet outing is one true " \
          "sentence: never pad it, never list the facts, and stop as soon as the story is told."
        ]
      end

      def sentence_instruction
        "Write at most #{sentence_range.max} sentences, and stop as soon as the story is told."
      end

      # The shape travels in the prompt too: a thinking mode and the
      # prompt-only fallback never receive a JSON Schema (AI.md §2, §4.3).
      def answer_shape
        "{\"title\": \"a short nickname\", \"sentences\": [{\"text\": \"one sentence\", " \
          "\"fact_ids\": [\"<a fact id>\"]}]}"
      end

      def user_sentence_line = "Sentences: usually one or two, #{sentence_range.max} at most."

      def context_line
        sport_name = fact_display("baseline:sport")
        date = fact_display("baseline:date")
        [ ("Sport: #{sport_name}" if sport_name), ("Date: #{date}" if date) ].compact.join(". ")
      end

      def fact_display(id) = facts.find { it.id == id }&.display

      # The facts travel apart from the course, and in two groups: what the
      # page already shows and what it does not. The grouping is the only hint
      # of importance, and it is about the screen, not about the story
      # (AI.md §4.2).
      def fact_block
        shown, rest = facts.reject { it.kind == "section" }.partition { SHOWN_KINDS.include?(it.kind) }
        sections = []
        sections << "Facts already shown on the workout page (rarely worth repeating):\n#{lines(shown)}" \
          if shown.any?
        sections << "Facts the page does not show:\n#{lines(ordered(rest))}" if rest.any?
        sections.join("\n\n")
      end

      # A stable thematic order, never the weight order: the table must not
      # suggest which fact is the story (AI.md §3.4).
      def ordered(items)
        items.sort_by { |item| [ Facts::KINDS.index(item.kind), company_rank(item), item.id ] }
      end

      # « Avec X » is the headline; a first outing or a habit is a detail.
      def company_rank(item) = item.id == "company:with" ? 0 : 1

      def lines(items) = items.map { |fact| "#{fact.id} | #{fact.display}" }.join("\n")

      # The route's sections travel apart: they describe the course, they never
      # compete with the facts for the summary's angle (AI.md §4.2).
      def course_block
        sections = facts.select { it.kind == "section" }
        return "" if sections.empty?

        "Course, in order from the start (id | section):\n" +
          sections.map { |section| "#{section.id} | #{section.display}" }.join("\n")
      end
    end
  end
end
