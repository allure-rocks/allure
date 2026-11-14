# frozen_string_literal: true

Rails.application.configure do
  config.i18n.available_locales = %i[fr en de es nl]
  config.i18n.default_locale = :fr

  # A missing translation should be loud in development and test, and quiet in
  # production — where falling back to English beats rendering an error.
  config.i18n.fallbacks = [ :en ]
  config.i18n.raise_on_missing_translations = !Rails.env.production?
end
