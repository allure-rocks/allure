# frozen_string_literal: true

require "digest"

module Allure
  module Withings
    # Signs in to Withings's private API once and resolves the account's
    # users (PLAN_REMOTE_IMPORTS.md §7c.1–7c.2). The sign-in is the Health
    # Mate application's own: the MD5 digest of the password travels in the
    # `hash` field, exactly as the application sends it, and the answer's
    # session id is the only credential Allure ever keeps — for the few hours
    # or minutes Withings grants it. The password itself never leaves this
    # call.
    class Session
      DEFAULT_DURATION = 900
      # Withings grants the duration the login asks for (observed
      # 2026-11-01: `duration=86400` answered `duration: 86400`, while the
      # 2019 reference merely asked 900). The provider signs in for a day
      # — PLAN_REMOTE_IMPORTS.md §7c.2 decision 9.
      DAILY_DURATION = 86_400
      LOGIN_PATH = "/cgi-bin/auth"
      USERS_PATH = "/cgi-bin/account"

      # The application identity the reference drives. The reference spells
      # the platform key `appfm` on `auth`/`account` and `apppfm` on the v2
      # endpoints; each call mirrors its own spelling rather than
      # normalising, so a server-side check sees what it expects.
      APP_FORM = { "appname" => "wiscaleNG", "appfm" => "ios", "appliver" => 4050301 }.freeze
      USERS_FORM = {
        "enrich" => "t",
        "recurse_devtype" => 1,
        "recurse_use" => 7,
        "listmask" => 7,
        "callctx" => "foreground,SyncForTracker,account"
      }.freeze
      STATUS_INVALID_CREDENTIALS = 100

      # `body` is the parsed login answer kept for the probe, which reports
      # the response's shape (masked); slice 5 reads only `session_id` and
      # `account_id`.
      SignedIn = Data.define(:session_id, :account_id, :body)

      def initialize(http: Http.new)
        @http = http
      end

      # Returns `SignedIn`, or raises.
      def sign_in(email:, password:, duration: DEFAULT_DURATION)
        response = @http.post_form(LOGIN_PATH, form: {
          "email" => email.to_s,
          "duration" => Integer(duration),
          "hash" => Digest::MD5.hexdigest(password.to_s),
          "callctx" => "foreground",
          "action" => "login"
        }.merge(APP_FORM))
        body = check(response)
        session_id = body.dig("body", "sessionid").to_s
        account_id = body.dig("body", "account", 0, "id")
        raise Error::Unavailable, "the login answer carries no session" if session_id.empty?

        SignedIn.new(session_id:, account_id:, body:)
      end

      # The account's users, as raw hashes (the shape varies; the probe
      # reports it). The first user's `id` is the `userid` every other call
      # needs.
      def users(signed_in)
        response = @http.post_form(USERS_PATH, form: {
          "action" => "getuserslist",
          "accountid" => signed_in.account_id,
          "sessionid" => signed_in.session_id
        }.merge(USERS_FORM).merge(APP_FORM))
        check(response).dig("body", "users") || []
      end

      private

      def check(response)
        raise Error::RateLimited, "HTTP 429" if response.status == 429
        raise Error::Unavailable, "HTTP #{response.status}" unless response.success?

        body = response.json
        raise Error::Unavailable, "the answer is not JSON" if body.nil?

        status = body["status"].to_i
        if status == STATUS_INVALID_CREDENTIALS
          raise Error::InvalidCredentials, "Withings refused the e-mail address or the password"
        end
        raise Error::ApiStatus.new(status, body["error"]) unless status.zero?

        body
      end
    end
  end
end
