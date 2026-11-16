# frozen_string_literal: true

module Allure
  module Withings
    # Failures of reading Withings's private Health Mate API
    # (docs/dev/REMOTE-IMPORTS.md). Messages never carry the password, the
    # session id or the userid.
    class Error < StandardError
      # The login refused the e-mail address or the password (status 100).
      class InvalidCredentials < Error; end

      # A non-zero Withings status. `status` carries the number so the probe
      # records which code means what before slice 5 freezes the mapping of
      # an expired session.
      class ApiStatus < Error
        attr_reader :status

        def initialize(status, api_message = nil)
          @status = status.to_i
          super("withings status #{@status}#{": #{api_message}" if api_message.to_s.present?}")
        end
      end

      # HTTP 429.
      class RateLimited < Error; end

      # A session that recorded neither a position nor a heart-rate sample:
      # there is no original to synthesize.
      class NoSamples < Error; end

      # Transport failure, timeout, 5xx or an unexpected answer.
      class Unavailable < Error; end
    end
  end
end
