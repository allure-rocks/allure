# frozen_string_literal: true

module Allure
  module Exr
    # Failures of reading the EXR account site (PLAN_REMOTE_IMPORTS.md §7b).
    # Messages never carry the password or a cookie value.
    class Error < StandardError
      # The site refused the e-mail address or the password.
      class InvalidCredentials < Error; end

      # The sign-in succeeded but set no remember cookie; Allure never keeps the
      # two-hour session alone.
      class NoRememberCookie < Error; end

      # The remember cookie no longer opens a session: the request landed on
      # the sign-in page.
      class SignedOut < Error; end

      # HTTP 429.
      class RateLimited < Error; end

      # HTTP 404.
      class NotFound < Error; end

      # Transport failure, timeout, 5xx or an unexpected answer.
      class Unavailable < Error; end
    end
  end
end
