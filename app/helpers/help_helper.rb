# frozen_string_literal: true

module HelpHelper
  # The « En savoir plus » link a screen puts beside a hint (DESIGN.md §20.20).
  def help_link(slug, **options)
    raise ArgumentError, "unknown help topic #{slug}" unless HelpController::TOPICS.key?(slug)

    link_to t("help.learn_more"), help_topic_path(slug), **options
  end
end
