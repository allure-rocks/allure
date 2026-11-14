# frozen_string_literal: true

# config/navigation.rb is data, not an autoloadable constant, so it is loaded
# explicitly. Re-loading on each reload keeps editing the tree a hot operation
# in development.
Rails.application.config.to_prepare do
  Allure::Navigation.reset!
  load Rails.root.join("config/navigation.rb")
end
