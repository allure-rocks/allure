require_relative "boot"
require_relative "version"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

# Development-only tools (AGENTS.md): the devtools engine is loaded in
# development and test only, and its directory is excluded from the production
# image and from the Docker build context. It must be required here, before
# `Rails.application.initialize!`, so its route set, views and locales are
# registered with the application.
require_relative "../devtools/lib/dev_tools" if Rails.env.local?

# Rack middleware is built once at boot and never reloaded, so it lives
# outside the autoloaded lib/ tree.
require_relative "../lib/middleware/request_body_limit"

module Allure
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks middleware])

    # Before Rack::MethodOverride, which already reads form bodies
    # (PLAN_IMPORT_SOURCES.md §3.2).
    config.middleware.insert_before 0, Allure::RequestBodyLimit

    # Federation orchestration is kept outside the generic service namespace so
    # protocol-facing code can grow without coupling it to browser workflows.
    config.autoload_paths << Rails.root.join("app/federation")
    config.eager_load_paths << Rails.root.join("app/federation")

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Don't generate system test files.
    config.generators.system_tests = nil

    # Error pages are rendered by ErrorsController through the full middleware
    # stack, so they get the layout, i18n and helpers rather than the static
    # public/*.html files.
    config.exceptions_app = routes

    # Private workout blobs are served only through application controllers so
    # an old signed Active Storage URL cannot bypass a visibility change.
    config.active_storage.draw_routes = false

    # A deleted actor must answer 410, not 404 — see Allure::Federation::TombstonedError.
    config.action_dispatch.rescue_responses["Allure::Federation::TombstonedError"] = :gone
  end
end
