# frozen_string_literal: true

module LanguageSwitcherHelper
  # The current page in another language. A page rendered by a failed POST has
  # no GET address of its own, so its switcher reloads the action's form.
  def language_switcher_path(locale)
    return "#{request.path}?#{request.query_parameters.merge("locale" => locale.to_s).to_query}" if request.get? || request.head?

    url_for(controller: controller_path, action: :new, locale:, only_path: true)
  rescue ActionController::UrlGenerationError
    root_path(locale:)
  end
end
