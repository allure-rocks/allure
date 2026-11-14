# frozen_string_literal: true

# The publication badge (DESIGN.md §10.4): one shape for every surface that
# states a workout's or a course's sharing state — owner cards, the list, the
# feed, the workout page, a course and the administration console.
#
# Every state carries the publication mark, so the colour is never the only
# cue (§18.6): public is green, followers blue, a publication waiting out its
# delay in its audience's tint with a slow pulse on the mark, and "not
# published" grey with the cut mark. It is a `BadgesHelper#state_badge`, so it follows the same
# responsive rule as every other state badge.
module PublicationBadgeHelper
  # One state, one mark, one tint, one wording. A scheduled publication takes
  # the tint of the audience it will reach and pulses: nothing is shared while
  # the delay runs, and its owner can still act on it
  # (PLAN_DELAYED_PUBLISHING.md).
  STATES = {
    "public" => { css: "bg-success-lt", icon: "ti-broadcast",
                  label: "workouts.publication.audience.public" },
    "followers" => { css: "bg-info-lt", icon: "ti-broadcast",
                     label: "workouts.publication.audience.followers" },
    "scheduled" => { icon: "ti-broadcast", pulse: true, label: "workouts.scheduled.badge" },
    "unpublished" => { css: "bg-secondary-lt", icon: "ti-broadcast-off",
                       label: "workouts.publication.unpublished" }
  }.freeze

  # A course states the same states with its own words, and its private one is
  # the "not published" state of the badge (DESIGN.md §20.6).
  SEGMENT_VISIBILITY_STATES = {
    "public" => "public", "followers_only" => "followers", "private" => "unpublished"
  }.freeze

  # `fit: :auto` prints the label from `md` up and falls back to the icon
  # alone below it; `fit: :icon` keeps the badge icon-only at every width, for
  # the rows that have no room for a word (the workout cards, the phone rows
  # of a list). `label` overrides the state's own wording — a course names its
  # own visibility, the console and the sharing card name the audience — and
  # `data` adds further data attributes. `audience` is the scheduled
  # publication's ("public" or "followers"), which gives the badge its tint.
  def publication_badge(state, fit: :auto, label: nil, audience: nil, data: {})
    spec = STATES.fetch(state.to_s) do
      raise ArgumentError, "unknown publication state: #{state.inspect}"
    end
    data = data.merge(audience_state: state)
    css = spec[:css]
    unless css
      audience = audience.to_s.presence || "public"
      css = STATES.fetch(audience) { raise ArgumentError, "unknown audience: #{audience.inspect}" }.fetch(:css)
      data[:audience] = audience
    end
    state_badge(css:, icon: spec[:icon], label: label || t(spec[:label]), fit:, pulse: spec[:pulse], data:)
  end

  # A course's own visibility in the same badge (DESIGN.md §20.6): the course
  # list row and its page header carry it, with the course's wording.
  def segment_visibility_badge(visibility, **options)
    visibility = visibility.to_s
    publication_badge(
      SEGMENT_VISIBILITY_STATES.fetch(visibility),
      label: t("segments.visibility.#{visibility}"),
      data: { segment_visibility: visibility },
      **options
    )
  end
end
