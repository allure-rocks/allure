# frozen_string_literal: true

module Allure
  module SportPalette
    # Icon families (DESIGN.md §6). Sport identity is icon + text only: a
    # family carries no colour and only supplies the fallback partial for a
    # slug the local catalog does not know (a remote sport).
    GROUPS = %w[run ride hike swim ski other].freeze

    # The 38 seeded sports. Every one ships its own inline SVG partial under
    # app/views/sports/icons/, in the Tabler 24-grid and stroke style, never a
    # webfont glyph.
    ALLURE_ICONS = %w[
      cycling
      cycling_road
      cycling_gravel
      cycling_electric
      cycling_trekking
      cycling_virtual
      mountain_biking
      mountain_biking_electric
      halfbike
      inline_skating
      running
      running_virtual
      trail
      walking
      hiking
      mountaineering
      snowshoes
      skiing_alpine
      skiing_touring
      skiing_cross_country
      snowboarding
      ice_skating
      pool_swimming
      open_water_swimming
      swimrun
      rowing
      rowing_virtual
      kayaking
      kayaking_whitewater
      canoeing
      canoeing_whitewater
      standup_paddleboarding
      windsurfing
      tennis_outdoor
      padel_outdoor
      paragliding
      strength_training
      fitness
    ].freeze

    # slug => render path (without the leading underscore).
    PARTIALS = ALLURE_ICONS.index_with { |slug| "sports/icons/#{slug}" }.freeze

    # group => render path for the family fallback.
    FAMILY_PARTIALS = GROUPS.index_with { |group| "sports/icons/families/#{group}" }.freeze

    module_function

    def icon(group) = FAMILY_PARTIALS.fetch(group.to_s)

    # Per-sport render path, or the family fallback path for an unknown slug.
    # Callers always render the result; no sport is ever drawn from the icon
    # font.
    def icon_for(slug, group) = PARTIALS[slug.to_s] || icon(group)

    def partial_for(slug) = PARTIALS[slug.to_s]
  end
end
