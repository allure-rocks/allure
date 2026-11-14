# frozen_string_literal: true

module ImportConnections
  module GarminConnect
    # Signs in to Garmin with the credentials a pending link holds
    # (PLAN_REMOTE_IMPORTS.md §7.2): the password on the first run, the
    # verification code on the next. Every branch wipes what it used; a
    # failure returns the connection to its previous state with the reason.
    # Never retried: each attempt is a sign-in Garmin counts.
    class LinkJob < ApplicationJob
      queue_as :remote_imports

      limits_concurrency key: ->(connection) { "link-#{connection.id}" }, duration: 10.minutes

      REASONS = {
        Allure::GarminConnect::Error::InvalidCredentials => "invalid_credentials",
        Allure::GarminConnect::Error::RateLimited => "rate_limited",
        Allure::GarminConnect::Error::Refused => "refused",
        Allure::GarminConnect::Error::TokenRejected => "token_rejected",
        Allure::GarminConnect::Error::Unavailable => "unavailable"
      }.freeze

      def perform(connection, sso: nil, di_token: nil)
        I18n.with_locale(connection.user.locale) do
          @connection = connection
          @linking = ImportConnections::Linking.new(connection)
          @region = Allure::GarminConnect::Region.new(connection.region)
          @sso = sso || Allure::GarminConnect::Sso.new(region: @region)
          @di_token = di_token || Allure::GarminConnect::DiToken.new(region: @region)
          run
        end
      end

      private

      def run
        return unless @connection.reload.pending?
        return @connection.with_lock { @linking.expire_stale! } if @connection.pending_expired?

        result = sign_in
        return unless result

        if result.is_a?(Allure::GarminConnect::Sso::MfaRequired)
          await_code(result)
        else
          finish(@di_token.exchange(ticket: result.ticket, service_url: result.service_url))
        end
      rescue Allure::GarminConnect::Error::MfaFailed
        @connection.update!(credentials: @connection.credentials.to_h.except("pending_mfa_code"),
                            last_sync_error: I18n.t("settings.connections.garmin_connect.errors.mfa_failed"))
      rescue Allure::GarminConnect::Error => error
        @connection.with_lock { @linking.reset!(REASONS.fetch(error.class, "unavailable")) }
      rescue StandardError => error
        @connection.with_lock { @linking.reset!("unavailable") }
        Rails.error.report(error, handled: true, context: { component: self.class.name, connection_id: @connection.id })
      end

      def sign_in
        credentials = @connection.credentials.to_h
        if @connection.status == "mfa_pending"
          code = credentials["pending_mfa_code"]
          return nil if code.blank?

          @sso.verify_mfa(state: credentials.fetch("mfa_state"), code:)
        else
          email = credentials["pending_email"]
          password = credentials["pending_password"]
          # The password is spent by this attempt whatever happens next.
          @connection.update!(credentials: credentials.except("pending_password"))
          raise Allure::GarminConnect::Error::InvalidCredentials, "no pending password" if password.blank?

          @sso.sign_in(email:, password:)
        end
      end

      def await_code(challenge)
        @connection.update!(
          status: "mfa_pending",
          pending_expires_at: ImportConnection::PENDING_LIFETIME.from_now,
          credentials: @connection.credentials.to_h.except("pending_password", "pending_mfa_code")
                                  .merge("mfa_state" => challenge.to_h.deep_stringify_keys, "mfa_method" => challenge.method)
        )
      end

      def finish(token)
        email = @connection.credential(:pending_email)
        @connection.update!(
          status: "linked",
          linked_at: Time.current,
          revoked_at: nil,
          pending_expires_at: nil,
          last_sync_error: nil,
          token_expires_at: token.expires_at,
          credentials: { "di_token" => token.access_token, "di_refresh_token" => token.refresh_token,
                         "di_client_id" => token.client_id }
        )
        Notifications::Withdraw.new(user: @connection.user, subject: @connection).call!
        name_account(email)
      end

      # The social profile proves the token against the API and names the
      # account; `displayName` is a UUID, so the full name or the e-mail is used.
      def name_account(email)
        profile = Providers.for(@connection).profile
        @connection.update!(external_account_id: profile["profileId"].to_s.presence,
                            external_account_name: profile["fullName"].presence || email)
      rescue Allure::RemoteImports::Error::AuthError
        Expiry.new(@connection).call
      rescue Allure::RemoteImports::Error
        @connection.update!(external_account_name: email) if @connection.external_account_name.blank?
      end
    end
  end
end
