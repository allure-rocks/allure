# frozen_string_literal: true

module Allure
  module Insights
    # The sport vocabulary a summary may borrow (docs/dev/AI.md §4.1). The
    # glossary of DESIGN.md §4 binds the interface; a summary should sound like
    # a training partner, and a training partner says "D+" or "bosse". The
    # families follow the sports' own practice, not the icon groups: kayaking is
    # not swimming and tennis is not running.
    #
    # A short list per family, never a glossary: the model borrows the register,
    # the facts keep the numbers. No word here carries a number or a unit, so
    # jargon can never replace a unit the verifier does not check.
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
          "cycling" => %w[D+ bosse col enrouler mouliner avaler relance],
          "running" => %w[D+ footing fractionné côte relance],
          "hiking" => %w[D+ crapahuter sentier grimpette sommet],
          "skiing" => %w[D+ peaux poudre piste descente],
          "swimming" => %w[longueurs bassin crawl virage coulée]
        },
        en: {
          "cycling" => %w[climbing spin grind big\ ring descending],
          "running" => %w[vert tempo negative\ split strides hills],
          "hiking" => %w[vert trail switchbacks scrambling summit\ push],
          "skiing" => %w[vert skinning powder laps],
          "swimming" => %w[lengths sets the\ wall flip\ turn]
        },
        de: {
          "cycling" => %w[Anstieg Rampe kurbeln großes\ Blatt Berg],
          "running" => %w[Tempolauf negativer\ Split Steigung Trabpause],
          "hiking" => %w[Aufstieg Gipfel Serpentinen Bergweg Hütte],
          "skiing" => %w[Felle Pulver Abfahrt Schwünge Piste],
          "swimming" => %w[Bahnen Kraul Wende Becken Zug]
        },
        es: {
          "cycling" => %w[desnivel repecho puerto rodar plato\ grande],
          "running" => %w[rodaje series cuestas negativo],
          "hiking" => %w[subida cumbre senda zigzag mochila],
          "skiing" => %w[pieles nieve\ polvo bajada giros pista],
          "swimming" => %w[largos crol viraje piscina brazada]
        },
        nl: {
          "cycling" => %w[hoogtemeters klim bult doortrappen grote\ plaat],
          "running" => %w[duurloop negatieve\ split heuveltjes versnellen],
          "hiking" => %w[klim top haarspeldbochten bergpad rugzak],
          "skiing" => %w[vellen poeder afdaling bochten piste],
          "swimming" => %w[baantjes borstcrawl keerpunt bad slag]
        }
      }.freeze

      module_function

      # The family of a sport slug, or nil for the sports whose vocabulary is
      # too thin (or too niche) to give a small model anything useful.
      def family(slug)
        FAMILIES.each { |name, slugs| return name if slugs.include?(slug.to_s) }
        nil
      end

      # The family's words in the member's language, or nil when the sport has
      # no family. Falls back to English like the rest of the prompt.
      def words(slug, locale:)
        name = family(slug)
        return nil unless name

        WORDS.fetch(locale.to_sym, WORDS[:en]).fetch(name, nil)
      end
    end
  end
end
