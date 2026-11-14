# frozen_string_literal: true

# config/release_notes.yml is data, not an autoloadable constant, and it is
# live-edited in development. Resetting the memoized load on each reload keeps
# that a hot operation, exactly like config/navigation.rb.
Rails.application.config.to_prepare do
  Allure::ReleaseNotes.reset!
end
