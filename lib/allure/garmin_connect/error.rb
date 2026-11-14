# frozen_string_literal: true

module Allure
  module GarminConnect
    # Failures of the unofficial Garmin Connect flow (PLAN_REMOTE_IMPORTS.md §7).
    # Messages never carry credentials, tokens or cookies.
    class Error < StandardError
      # Garmin answered INVALID_USERNAME_PASSWORD: stop, never try another strategy.
      class InvalidCredentials < Error; end

      # A bot challenge (CAPTCHA_REQUIRED, Cloudflare 403 or an HTML body).
      class Refused < Error; end

      # HTTP 429, or a 429 buried in a JSON error body.
      class RateLimited < Error; end

      # The verification code was not accepted.
      class MfaFailed < Error; end

      # The DI token could not be obtained or refreshed, or the API rejected it.
      class TokenRejected < Error; end

      # The API answered 404.
      class NotFound < Error; end

      # Transport failure, timeout, 5xx or an unexpected answer.
      class Unavailable < Error; end
    end
  end
end
