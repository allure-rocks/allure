# frozen_string_literal: true

module Allure
  module Insights
    # The sport vocabulary a summary may borrow (docs/dev/AI.md §4.1). The
    # glossary of DESIGN.md §4 binds the interface; a summary should sound like
    # a training partner, and a training partner says "bosse" or "col". The
    # families follow the sports' own practice, not the icon groups: kayaking is
    # not swimming and tennis is not running.
    #
    # The list is a hint, never an instruction: the prompt asks for one word at
    # most, and says that most summaries need none. A climb word is only
    # offered when the outing actually climbed, so a flat ride is never told to
    # talk about its "col". No word here carries a number or a unit, so jargon
    # can never replace a unit the verifier does not check.
    module Jargon
      FAMILIES = {
        "cycling" => %w[
          cycling cycling_road cycling_gravel cycling_electric cycling_trekking
          cycling_virtual mountain_biking mountain_biking_electric
        ],
        "running" => %w[running running_virtual trail],
        "hiking" => %w[walking hiking mountaineering snowshoes],
        "skiing" => %w[skiing_alpine skiing_touring skiing_cross_country snowboarding],
        "swimming" => %w[pool_swimming open_water_swimming swimrun]
      }.freeze

      WORDS = {
        fr: {
          "cycling" => { general: %w[enrouler mouliner relance], climb: %w[bosse col] },
          "running" => { general: %w[footing relance], climb: %w[côte] },
          "hiking" => { general: %w[crapahuter sentier], climb: %w[grimpette sommet] },
          "skiing" => { general: %w[peaux poudre], climb: [] },
          "swimming" => { general: %w[longueurs coulée], climb: [] }
        },
        en: {
          "cycling" => { general: %w[spin], climb: %w[climbing grind] },
          "running" => { general: %w[steady strides], climb: %w[hills] },
          "hiking" => { general: %w[trail switchbacks], climb: %w[summit] },
          "skiing" => { general: %w[skinning powder], climb: [] },
          "swimming" => { general: %w[lengths kick], climb: [] }
        },
        de: {
          "cycling" => { general: %w[kurbeln], climb: %w[Anstieg Rampe] },
          "running" => { general: %w[Trabpause Tempolauf], climb: %w[Steigung] },
          "hiking" => { general: %w[Bergweg Serpentinen], climb: %w[Gipfel] },
          "skiing" => { general: %w[Felle Pulver], climb: [] },
          "swimming" => { general: %w[Bahnen Kraul], climb: [] }
        },
        es: {
          "cycling" => { general: %w[rodar], climb: %w[repecho puerto] },
          "running" => { general: %w[rodaje series], climb: %w[cuestas] },
          "hiking" => { general: %w[senda zigzag], climb: %w[cumbre] },
          "skiing" => { general: %w[pieles], climb: [] },
          "swimming" => { general: %w[largos crol], climb: [] }
        },
        nl: {
          "cycling" => { general: %w[doortrappen], climb: %w[klim bult] },
          "running" => { general: %w[duurloop versnellen], climb: %w[heuveltjes] },
          "hiking" => { general: %w[bergpad haarspeldbochten], climb: %w[top] },
          "skiing" => { general: %w[vellen poeder], climb: [] },
          "swimming" => { general: %w[baantjes borstcrawl], climb: [] }
        }
      }.freeze

      # Two ordinary words, plus one climb word when the outing climbed: three
      # at most, so the model borrows a register instead of a glossary.
      WORD_LIMIT = 3

      module_function

      # The family of a sport slug, or nil for the sports whose vocabulary is
      # too thin (or too niche) to give a small model anything useful.
      def family(slug)
        FAMILIES.each { |name, slugs| return name if slugs.include?(slug.to_s) }
        nil
      end

      # The words to offer, or nil when the sport has no family: a sport with
      # no list gets no jargon line, so the model invents none.
      def words(slug, locale:, climbing: false)
        name = family(slug)
        return nil unless name

        entries = WORDS.fetch(locale.to_sym, WORDS[:en]).fetch(name, {})
        general = Array(entries[:general]).first(2)
        climb = climbing ? Array(entries[:climb]).first(1) : []
        list = (general + climb).first(WORD_LIMIT)
        list.presence
      end
    end
  end
end
