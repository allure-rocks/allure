# frozen_string_literal: true

require "time"

module Allure
  module Zwift
    # Exchanges the account's password or refresh token for an access token
    # (PLAN_REMOTE_IMPORTS.md §7d.1). Zwift's sign-in is a standard Keycloak
    # password grant; the application keeps only the refresh token, never the
    # password.
    #
    # The probe observed `expires_in` in seconds on 2026-11-05 (3 600 for an
    # hour) and a refresh token good for eight days (691 200), rotated on
    # every refresh. An older reference client saw milliseconds; a value above
    # the threshold is still read as milliseconds, and the raw value stays on
    # the answer for the probe.
    class Auth
      TOKEN_PATH = "/auth/realms/zwift/protocol/openid-connect/token"
      LOGOUT_PATH = "/auth/realms/zwift/tokens/logout"
      CLIENT_ID = "Zwift_Mobile_Link"
      MILLISECOND_THRESHOLD = 1_000_000

      Tokens = Data.define(:access_token, :refresh_token, :expires_at, :expires_in,
                           :refresh_expires_in, :refresh_expires_at, :raw) do
        def initialize(access_token:, refresh_token: nil, expires_at: nil, expires_in: nil,
                       refresh_expires_in: nil, refresh_expires_at: nil, raw: nil)
          super
        end
      end

      def initialize(http: Http.new)
        @http = http
      end

      def sign_in(email:, password:)
        request({ "grant_type" => "password", "username" => email.to_s, "password" => password.to_s },
                invalid: Error::InvalidCredentials)
      end

      def refresh(refresh_token:)
        request({ "grant_type" => "refresh_token", "refresh_token" => refresh_token.to_s },
                invalid: Error::RefreshRejected, fallback_refresh_token: refresh_token)
      end

      # Best effort, for unlinking: the provider swallows every failure.
      def logout(refresh_token:)
        @http.post_form(LOGOUT_PATH, form: { "client_id" => CLIENT_ID, "refresh_token" => refresh_token.to_s })
      end

      private

      def request(grant, invalid:, fallback_refresh_token: nil)
        response = @http.post_form(TOKEN_PATH, form: { "client_id" => CLIENT_ID }.merge(grant))
        if response.status == 429
          raise Error::RateLimited.new(response.retry_after, "token endpoint: HTTP 429")
        end
        if [ 400, 401 ].include?(response.status)
          raise invalid, "the token endpoint refused the grant (HTTP #{response.status})"
        end
        raise Error::Unavailable, "token endpoint: HTTP #{response.status}" unless response.success?

        body = response.json
        raise Error::Unavailable, "token endpoint: the answer is not JSON" if body.nil?

        access_token = body["access_token"].to_s
        raise Error::Unavailable, "token endpoint: no access token" if access_token.empty?

        refresh_token = body["refresh_token"].to_s
        expires_in = body["expires_in"]
        refresh_expires_in = body["refresh_expires_in"]
        seconds = expires_in_seconds(expires_in)
        refresh_seconds = expires_in_seconds(refresh_expires_in)
        Tokens.new(
          access_token:,
          refresh_token: refresh_token.empty? ? fallback_refresh_token : refresh_token,
          expires_at: seconds && Time.now + seconds,
          expires_in:,
          refresh_expires_in:,
          refresh_expires_at: refresh_seconds && Time.now + refresh_seconds,
          raw: body
        )
      end

      def expires_in_seconds(value)
        return nil if value.nil?

        seconds = value.to_f
        return nil unless seconds.positive?

        seconds > MILLISECOND_THRESHOLD ? seconds / 1000.0 : seconds
      end
    end
  end
end
