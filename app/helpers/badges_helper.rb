# frozen_string_literal: true

# The state badges (DESIGN.md §10.4): one shape for the publication state, the
# viewer's own items and the activities done with someone. Each carries its
# icon, so the colour is never the only cue (§18.6), and its label is always in
# the DOM — printed from `md` up, and only visually hidden below it, where the
# badge keeps its icon alone and a tooltip names it.
module BadgesHelper
  # Below Bootstrap's `md` the label is visually hidden and the tooltip takes
  # over, so the tooltip only exists where it is needed. Kept in sync with the
  # `.allure-badge-responsive` rules of `components/_badges.scss`.
  ICON_ONLY_MEDIA = "(max-width: 767.98px)"

  # The viewer's own item: « À moi » on a course of theirs, « Vous » on their
  # own publication in the feed.
  def mine_badge(label:, fit: :auto)
    state_badge(css: "bg-primary-lt", icon: "ti-user-circle", label:, fit:, data: { badge: "mine" })
  end

  # An activity done with someone (PLAN_TOGETHER.md, DESIGN.md §10.18): it
  # links to the source while the viewer may open it, and turns grey once the
  # source is deleted. `tooltip` carries the full list of names when the label
  # shortens it.
  def together_badge(label, href: nil, detached: false, fit: :auto, tooltip: nil)
    state_badge(css: detached ? "bg-secondary-lt" : "bg-primary-lt", icon: "ti-users", label:, fit:,
                href:, tooltip:, data: { badge: "together" })
  end

  # `fit: :auto` prints the label from `md` up and falls back to the icon
  # alone below it; `fit: :icon` keeps the badge icon-only at every width, for
  # the rows that have no room for a word (the workout cards, the phone rows
  # of a list). With `href` the badge is a link, focusable on its own. A
  # `tooltip` longer than the label shows at every width.
  def state_badge(css:, icon:, label:, fit: :auto, href: nil, data: {}, pulse: false, tooltip: nil)
    icon_only = fit.to_sym == :icon
    full = tooltip.presence || label
    classes = class_names(
      "badge", css,
      "allure-badge-icon" => icon_only,
      "allure-badge-responsive" => !icon_only,
      "allure-badge-pulse" => pulse
    )
    # An icon-only badge only ever has its tooltip; the responsive one keeps it
    # for the widths where the label is hidden, unless the label is shortened.
    always = icon_only || full != label
    tooltip_attributes = always ? tooltip_data(full) : tooltip_data(label, media: ICON_ONLY_MEDIA)
    content = tag.i(class: "ti #{icon} me-1", aria: { hidden: true }) +
              (icon_only ? tag.span(full, class: "visually-hidden") : tag.span(label, class: "allure-badge-responsive__label"))
    attributes = { class: classes, data: data.merge(tooltip_attributes) }
    return link_to(content, href, **attributes) if href

    tag.span(content, **attributes, tabindex: ("0" if always))
  end
end
