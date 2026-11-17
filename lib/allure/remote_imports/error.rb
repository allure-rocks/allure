# frozen_string_literal: true

module Allure
  module RemoteImports
    # The failures every provider adapter raises (docs/dev/REMOTE-IMPORTS.md),
    # whatever its own client calls them.
    class Error < StandardError
      # The link must be redone: the connection turns `expired`.
      class AuthError < Error; end

      # The provider's session reached its natural end (Withings's day-long
      # session, §7c.2 decision 9). Like an `AuthError` the connection turns
      # `expired`, but the end is expected: no notification is sent, queued
      # work is left in place, and the owner resumes it by connecting again.
      class SessionEnded < Error; end

      # The activity was announced with a route but its fetch carried too few
      # positions for one (Withings's sparse `getvasistas` location answer,
      # §7c.3): the entry is skipped as `no_geometry` when the connection
      # imports positioned sessions only.
      class NoGeometry < Error; end

      # The provider's quota is spent; work resumes at `retry_at`.
      class RateLimited < Error
        attr_reader :retry_at

        def initialize(message = nil, retry_at:)
          @retry_at = retry_at
          super(message)
        end
      end

      # Transient: retried later.
      class Unavailable < Error; end

      # The activity has no file (a manual entry): the entry is skipped.
      class NotFound < Error; end

      # A bot challenge at sign-in.
      class Refused < Error; end
    end
  end
end
