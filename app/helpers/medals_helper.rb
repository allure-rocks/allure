# frozen_string_literal: true

# Records and ranks (DESIGN.md §10.4). The shape says who you measure against,
# the colour says the place:
#
# - the trophy is a personal place, you against yourself: gold for the record,
#   silver and bronze for the second and third best time (owner-only);
# - the laurel wreath before a numeral is a leaderboard place, you against
#   others: gold, silver and bronze for the top three, the numeral alone after.
#
# The two shapes never swap meanings. Colour is never the only encoding
# (§18.6): every mark carries a tooltip and a spoken label.
module MedalsHelper
  MEDAL_TIERS = { 1 => "gold", 2 => "silver", 3 => "bronze" }.freeze
  PLACE_KEYS = { "gold" => "medals.first", "silver" => "medals.second", "bronze" => "medals.third" }.freeze
  PERSONAL_PLACE_KEYS = { 1 => "medals.record", 2 => "medals.personal_place.second", 3 => "medals.personal_place.third" }.freeze
  PERSONAL_PLACE_SHORT_KEYS = {
    1 => "medals.personal_place_short.first",
    2 => "medals.personal_place_short.second",
    3 => "medals.personal_place_short.third"
  }.freeze

  # A leaderboard place: the numeral alone from fourth place on, preceded for
  # the top three by the laurel of its place in the medal's colour. The
  # numeral speaks its rank; the top three also carry the place tooltip.
  # `participants` renders the board size as the single `/ 12` suffix.
  def rank_medal(rank, participants: nil)
    tier = MEDAL_TIERS[rank]
    spoken = tag.span(rank.to_s, aria: { hidden: true }) + tag.span(t("medals.rank", rank: rank), class: "visually-hidden")
    mark = if tier
      numeral = tag.span(spoken, class: "allure-rank-numeral", data: tooltip_data(t(PLACE_KEYS.fetch(tier))))
      tag.span(class: "allure-rank") do
        tag.i(class: "ti ti-laurel-wreath-#{rank} allure-medal allure-medal--#{tier}", aria: { hidden: true }) + numeral
      end
    else
      tag.span(spoken, class: "allure-rank-numeral")
    end
    return mark unless participants

    tag.span(class: "text-nowrap") do
      mark + tag.span(" / #{participants}", class: "text-secondary small")
    end
  end

  # The summary-tile stamp of a leaderboard place: the laurel on its tier's
  # tinted disc. Nil outside the top three.
  def rank_stamp(rank)
    tier = MEDAL_TIERS[rank]
    return nil unless tier

    { icon: "ti-laurel-wreath-#{rank}", css: "allure-stamp--#{tier}", label: t(PLACE_KEYS.fetch(tier)) }
  end

  # The complete sentence for a personal place: « Record : 10 km »,
  # « 2e meilleur temps : 10 km ». Nil outside the top three.
  def personal_place_label(place, subject)
    key = PERSONAL_PLACE_KEYS[place]
    key && t(key, record: subject)
  end

  # A personal place beside the value it qualifies (a secondary metric, a
  # best-effort row, a climb, an own segment effort): the bare trophy in the
  # place's colour. Nil outside the top three.
  def personal_place_icon(place, subject, extra_classes: nil)
    tooltip = personal_place_label(place, subject)
    return nil unless tooltip

    tag.span(class: extra_classes, data: tooltip_data(tooltip)) do
      trophy_icon(place) + tag.span(tooltip, class: "visually-hidden")
    end
  end

  # A personal place in a badge row: the neutral pill holding the trophy and
  # its short label (`RP`/`PB`, `2e`/`2nd`, `3e`/`3rd`, or `Record` when
  # `text:` is given). `compact: true` keeps the trophy alone in the pill, the
  # tooltip and accessible label naming it (workout cards). Nil outside the
  # top three.
  def personal_place_badge(place, tooltip:, text: nil, extra_classes: nil, compact: false)
    return nil unless MEDAL_TIERS.key?(place)

    if compact
      return tag.span(class: [ "badge", "bg-secondary-lt", "allure-place-badge", "allure-badge-icon", extra_classes ].compact.join(" "),
                      role: "img", tabindex: 0, aria: { label: tooltip }, data: tooltip_data(tooltip)) do
        trophy_icon(place)
      end
    end

    text ||= t(PERSONAL_PLACE_SHORT_KEYS.fetch(place))
    tag.span(class: [ "badge", "bg-secondary-lt", "allure-place-badge", extra_classes ].compact.join(" "),
             aria: { label: tooltip }, data: tooltip_data(tooltip)) do
      safe_join([ trophy_icon(place, "me-1"), text ])
    end
  end

  # The summary-tile stamp of a personal place: the trophy on its tier's
  # tinted disc. `tooltip` is the complete translated sentence. Nil outside
  # the top three.
  def personal_place_stamp(place, tooltip:)
    tier = MEDAL_TIERS[place]
    return nil unless tier

    { icon: "ti-trophy", css: "allure-stamp--#{tier}", label: tooltip }
  end

  private

  def trophy_icon(place, extra_classes = nil)
    tier = MEDAL_TIERS.fetch(place)
    tag.i(class: [ "ti", "ti-trophy", "allure-medal", "allure-medal--#{tier}", extra_classes ].compact.join(" "),
          aria: { hidden: true })
  end
end
