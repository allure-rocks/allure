# frozen_string_literal: true

module ImportConnections
  module Zwift
    # Signs in to Zwift's mobile API once with the password a pending link
    # holds (PLAN_REMOTE_IMPORTS.md §7d.2) and keeps only the refresh token and
    # the athlete id. The password is wiped before the request; a failure
    # returns the connection to its previous state with the reason. Once
    # linked, the job verifies the token with one profile call and resumes the
    # connection's interrupted batches. Never retried.
    class LinkJob < ApplicationJob
      queue_as :remote_imports

      limits_concurrency key: ->(connection, **) { "link-#{connection.id}" }, duration: 10.minutes

      REASONS = {
        Allure::Zwift::Error::InvalidCredentials => "invalid_credentials",
        Allure::Zwift::Error::RefreshRejected => "unavailable",
        Allure::Zwift::Error::SignedOut => "unavailable",
        Allure::Zwift::Error::RateLimited => "rate_limited",
        Allure::Zwift::Error::Unavailable => "unavailable"
      }.freeze

      def perform(connection, session: nil)
        I18n.with_locale(connection.user.locale) do
          @connection = connection
          @linking = ImportConnections::Linking.new(connection)
          @session = session || Allure::Zwift::Auth.new
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
        raise Allure::Zwift::Error::InvalidCredentials, "no pending password" if password.blank?

        tokens = @session.sign_in(email:, password:)
        @tokens = tokens
        player_id = client(tokens).player_id
        finish(@tokens, player_id, email)
      rescue Allure::Zwift::Error => error
        @connection.with_lock { @linking.reset!(REASONS.fetch(error.class, "unavailable")) }
      rescue StandardError => error
        @connection.with_lock { @linking.reset!("unavailable") }
        Rails.error.report(error, handled: true, context: { component: self.class.name, connection_id: @connection.id })
      end

      def client(tokens)
        Allure::Zwift::Client.new(
          refresh_token: tokens.refresh_token,
          access_token: tokens.access_token,
          expires_at: tokens.expires_at,
          on_tokens: ->(rotated) { @tokens = rotated }
        )
      end

      def finish(tokens, player_id, email)
        @connection.update!(
          status: "linked",
          linked_at: Time.current,
          revoked_at: nil,
          pending_expires_at: nil,
          last_sync_error: nil,
          token_expires_at: tokens.refresh_expires_at || tokens.expires_at,
          external_account_id: player_id.to_s,
          external_account_name: email,
          credentials: { "refresh_token" => tokens.refresh_token, "player_id" => player_id.to_s }
        )
        Notifications::Withdraw.new(user: @connection.user, subject: @connection).call!
        verify
        resume_interrupted_batches if @connection.reload.linked?
      end

      # One authenticated profile call proves the refresh token opens the
      # account; the provider persists the token the refresh rotates.
      def verify
        Providers.for(@connection).verify!
      rescue Allure::RemoteImports::Error::AuthError
        Expiry.new(@connection).call
      rescue Allure::RemoteImports::Error
        nil
      end

      # A token that died mid-batch leaves its entries queued; the
      # reconnection resumes every one of them (§7d.2).
      def resume_interrupted_batches
        @connection.interrupted_batches.find_each do |batch|
          Workouts::RemoteImportBatchJob.perform_later(batch)
        end
      end
    end
  end
end
