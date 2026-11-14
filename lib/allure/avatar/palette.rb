# frozen_string_literal: true

module Allure
  module Avatar
    # Curated pink palette for generated avatars (DESIGN.md §9.2). Backgrounds
    # are deep roses, pinks and magentas chosen so white holds 4.5:1 against
    # every entry, in both themes (proven by the contrast spec). Accents are
    # lighter pinks used by the decorative geometry only.
    module Palette
      COLOURS = %w[
        #a61e4d #c2255c #bf1650 #b02a6f #b3205f #b9256b
        #9a2b6b #a12d7a #ae3ec9 #9c36b5 #862e9c #d6336c
      ].freeze

      ACCENTS = %w[
        #f783ac #faa2c1 #e64980 #fcc2d7 #da77f2 #e599f7
      ].freeze
    end
  end
end
