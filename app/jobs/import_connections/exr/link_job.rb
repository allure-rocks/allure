# frozen_string_literal: true

module ImportConnections
  module Exr
    # Signs in to the EXR account site once with the password a pending link
    # holds (docs/dev/REMOTE-IMPORTS.md) and keeps only the remember cookie.
    # The password is wiped before the request; a failure returns the
    # connection to its previous state with the reason. Never retried.
    class LinkJob < ApplicationJob
      queue_as :remote_imports

      limits_concurrency key: ->(connection, **) { "link-#{connection.id}" }, duration: 10.minutes

      REASONS = {
        Allure::Exr::Error::InvalidCredentials => "invalid_credentials",
        Allure::Exr::Error::NoRememberCookie => "no_remember",
        Allure::Exr::Error::RateLimited => "rate_limited",
        Allure::Exr::Error::Unavailable => "unavailable"
      }.freeze

      def perform(connection, session: nil)
        I18n.with_locale(connection.user.locale) do
          @connection = connection
          @linking = ImportConnections::Linking.new(connection)
          @session = session || Allure::Exr::Session.new
          run
        end
      end

      private

      def run
        return unless @connection.reload.status == "pending"
        return @connection.with_lock { @linking.expire_stale! } if @connection.pending_expired?

        email = @connection.credential(:pending_email)
        password = @connection.credential(:pending_password)
        @connection.update!(credentials: @connection.credentials.to_h.except("pending_password"))
        raise Allure::Exr::Error::InvalidCredentials, "no pending password" if password.blank?

        finish(@session.sign_in(email:, password:), email)
      rescue Allure::Exr::Error => error
        @connection.with_lock { @linking.reset!(REASONS.fetch(error.class, "unavailable")) }
      rescue StandardError => error
        @connection.with_lock { @linking.reset!("unavailable") }
        Rails.error.report(error, handled: true, context: { component: self.class.name, connection_id: @connection.id })
      end

      def finish(cookie, email)
        @connection.update!(
          status: "linked",
          linked_at: Time.current,
          revoked_at: nil,
          pending_expires_at: nil,
          last_sync_error: nil,
          token_expires_at: cookie.expires_at,
          external_account_name: email,
          credentials: { "remember_cookie_name" => cookie.name, "remember_cookie" => cookie.value }
        )
        Notifications::Withdraw.new(user: @connection.user, subject: @connection).call!
        verify
      end

      # The session list proves the cookie alone opens the account.
      def verify
        Providers.for(@connection).verify!
      rescue Allure::RemoteImports::Error::AuthError
        Expiry.new(@connection).call
      rescue Allure::RemoteImports::Error
        nil
      end
    end
  end
end
