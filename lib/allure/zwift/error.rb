# frozen_string_literal: true

module Allure
  module Zwift
    # Failures of reading Zwift's mobile API (docs/dev/REMOTE-IMPORTS.md).
    # Messages never carry the password, the access token or the refresh
    # token.
    class Error < StandardError
      # The token endpoint refused the password grant.
      class InvalidCredentials < Error; end

      # The token endpoint refused the refresh grant: the connection's
      # refresh token has died and the owner must sign in again.
      class RefreshRejected < Error; end

      # An API call answered 401 even after a refresh: the access token is
      # dead and the provider treats the connection as expired.
      class SignedOut < Error; end

      # HTTP 429. `retry_after` is the server's hint in seconds, when it
      # sent one.
      class RateLimited < Error
        attr_reader :retry_after

        def initialize(retry_after = nil, message = nil)
          @retry_after = retry_after
          super(message)
        end
      end

      # HTTP 404, or an activity that carries no FIT file.
      class NotFound < Error; end

      # Transport failure, timeout, 5xx or an unexpected answer.
      class Unavailable < Error; end
    end
  end
end
