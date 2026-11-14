# frozen_string_literal: true

require Rails.root.join("lib/allure/auth/config")

# Keep CSRF state across native app restarts, just like the sign-in cookie.
# Authentication still enforces the Session row's idle and absolute lifetimes.
Rails.application.config.session_store :cookie_store,
  key: "_allure_session",
  expire_after: Allure::Auth::Config.session_max_lifetime
