# frozen_string_literal: true

module ImportConnections
  module Withings
    # Signs in to Withings's private API with the password a pending link
    # holds (docs/dev/REMOTE-IMPORTS.md) and keeps only the session, which
    # Withings grants for the asked duration — a day. The password is wiped
    # before the request; a failed sign-in returns the connection to its
    # previous state with the reason. Once linked, the job resumes the
    # connection's interrupted batches (a session that died mid-batch leaves
    # them queued, §7c.2); the owner picks a range to retrieve from the
    # connected card. Never retried.
    class LinkJob < ApplicationJob
      queue_as :remote_imports

      limits_concurrency key: ->(connection, **) { "link-#{connection.id}" }, duration: 10.minutes

      REASONS = {
        Allure::Withings::Error::InvalidCredentials => "invalid_credentials",
        Allure::Withings::Error::RateLimited => "rate_limited",
        Allure::Withings::Error::Unavailable => "unavailable"
      }.freeze

      def perform(connection, session: nil)
        I18n.with_locale(connection.user.locale) do
          @connection = connection
          @linking = ImportConnections::Linking.new(connection)
          @session = session || Allure::Withings::Session.new
          run
        end
      end

      private

      def run
        return unless @connection.reload.status == "pending"
        return @connection.with_lock { @linking.expire_stale! } if @connection.pending_expired?
        return unless (linked = sign_in)

        finish(*linked)
        verify
        resume_interrupted_batches if @connection.reload.linked?
      rescue StandardError => error
        # Past the sign-in, a linked account keeps its session; a row the
        # failure left pending returns to its previous state.
        @connection.with_lock { @linking.reset!("unavailable") if @connection.reload.pending? }
        Rails.error.report(error, handled: true, context: { component: self.class.name, connection_id: @connection.id })
      end

      # Signs in and answers the session id, the userid and the e-mail, or
      # nil after returning the row to its previous state with the reason.
      def sign_in
        email = @connection.credential(:pending_email)
        password = @connection.credential(:pending_password)
        @connection.update!(credentials: @connection.credentials.to_h.except("pending_password"))
        raise Allure::Withings::Error::InvalidCredentials, "no pending password" if password.blank?

        signed_in = @session.sign_in(email:, password:, duration: Allure::Withings::Session::DAILY_DURATION)
        user_id = @session.users(signed_in).dig(0, "id")
        raise Allure::Withings::Error::Unavailable, "no user in the account answer" if user_id.to_s.empty?

        [ signed_in.session_id, user_id, email ]
      rescue Allure::Withings::Error => error
        @connection.with_lock { @linking.reset!(REASONS.fetch(error.class, "unavailable")) }
        nil
      rescue StandardError => error
        @connection.with_lock { @linking.reset!("unavailable") }
        Rails.error.report(error, handled: true, context: { component: self.class.name, connection_id: @connection.id })
        nil
      end

      def finish(session_id, user_id, email)
        @connection.update!(
          status: "linked",
          linked_at: Time.current,
          revoked_at: nil,
          pending_expires_at: nil,
          last_sync_error: nil,
          token_expires_at: Allure::Withings::Session::DAILY_DURATION.seconds.from_now,
          external_account_id: user_id.to_s,
          external_account_name: email,
          credentials: { "sessionid" => session_id, "userid" => user_id }
        )
        Notifications::Withdraw.new(user: @connection.user, subject: @connection).call!
      end

      # One authenticated listing proves the session opens the account.
      def verify
        Providers.for(@connection).verify!
      rescue Allure::RemoteImports::Error::AuthError, Allure::RemoteImports::Error::SessionEnded
        Expiry.new(@connection, notify: false).call
      rescue Allure::RemoteImports::Error
        nil
      end

      # A session that died mid-batch leaves its entries queued; the
      # reconnection resumes every one of them (§7c.2).
      def resume_interrupted_batches
        @connection.interrupted_batches.find_each do |batch|
          Workouts::RemoteImportBatchJob.perform_later(batch)
        end
      end
    end
  end
end
