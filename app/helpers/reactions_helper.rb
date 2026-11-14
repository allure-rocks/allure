# frozen_string_literal: true

# Presentation rules for the reaction bar (PLAN_REACTIONS.md §4.4, DESIGN.md
# §10.17). The same component serves a local publication and a received note,
# and a page computes its summaries once for every card it renders.
module ReactionsHelper
  ICONS = {
    "beer" => "ti-beer",
    "energy" => "ti-bolt",
    "coffee" => "ti-coffee",
    "like" => "ti-thumb-up"
  }.freeze

  # The page's targets are summarised once; a target the controller did not
  # announce is summarised on its own instead of silently reading as empty.
  def reaction_summary_for(target)
    @reaction_summaries ||= Reactions::Summaries.new(
      targets: @reaction_targets.presence || [ target ],
      viewer: current_user&.actor, user: current_user
    ).call
    @reaction_summaries[target] ||= Reactions::Summaries.new(
      targets: [ target ], viewer: current_user&.actor, user: current_user
    ).call.fetch(target, Reactions::Summaries::EMPTY)
  end

  def reaction_bar_dom_id(target)
    "reaction-bar-#{target.model_name.name.underscore.dasherize}-#{target.id}"
  end

  def reaction_kind_icon(kind) = ICONS.fetch(kind.to_s, ICONS.fetch(Reaction::DEFAULT_KIND))

  def reaction_kind_label(kind) = t("reactions.kinds.#{kind}")

  def reaction_update_path_for(target)
    target.is_a?(RemoteNote) ? remote_note_reaction_path(target) : workout_reaction_path(target)
  end

  def reaction_button_label(kind, count)
    t("reactions.button.label", kind: reaction_kind_label(kind), count:)
  end

  # Three visual states (DESIGN.md §10.17): a ghost while nobody reacted,
  # emphasised as soon as one reaction of the type exists, and the brand tint
  # for the viewer's own reaction on top of the pressed attribute.
  def reaction_pill_classes(count:, mine:)
    class_names(
      "allure-reactions__pill",
      "allure-reactions__pill--active": count.positive?,
      "allure-reactions__pill--empty": count.zero?,
      "allure-reactions__pill--mine": mine
    )
  end

  # The shared tooltip data every icon-only control uses (ApplicationHelper).
  def reaction_tooltip_data(title)
    tooltip_data(title)
  end

  # The pill's tooltip (DESIGN.md §10.17): an empty pill names the gesture, a
  # populated one names who reacted — the newest reactors, the viewer as
  # « Vous » leading the list, then the rest as other people. The owner of a
  # workout reads the gesture addressed to them; every other reader reads it on
  # this activity. Deleted, blocked and deactivated accounts were already
  # dropped by the summary, and so were the reactors of an audience the viewer
  # may not read; when nobody is left to name, the sentence counts people.
  def reaction_pill_tooltip_data(summary, kind, target)
    return reaction_tooltip_data(reaction_action_tooltip(summary, kind)) if summary.count(kind).zero?

    shown = summary.reactors(kind).first(Reactions::Summaries::NAMES_LIMIT)
    viewer = shown.find { |actor| actor.user_id.present? && actor.user_id == current_user&.id }
    shown = [ viewer, *shown.reject { |actor| actor.id == viewer.id } ] if viewer
    names = shown.map { |actor| actor.id == viewer&.id ? t("reactions.tooltip.you") : actor_name(actor) }
    others = summary.count(kind) - names.size
    if names.empty?
      names << t("reactions.tooltip.people", count: others)
    elsif others.positive?
      names << t("reactions.tooltip.others", count: others)
    end
    sentence = names.to_sentence(words_connector: t("reactions.tooltip.names.words_connector"),
                                 two_words_connector: t("reactions.tooltip.names.last_word_connector"),
                                 last_word_connector: t("reactions.tooltip.names.last_word_connector"))
    key = if target.is_a?(Workout) && target.user_id == current_user&.id
      "owner"
    elsif viewer
      "self"
    else
      "reaction"
    end
    reaction_tooltip_data(t("reactions.tooltip.#{kind}.#{key}", names: sentence, count: summary.count(kind)))
  end

  def reaction_action_tooltip(summary, kind)
    t(summary.mine?(kind) ? "reactions.button.remove" : "reactions.button.react", kind: reaction_kind_label(kind))
  end
end
