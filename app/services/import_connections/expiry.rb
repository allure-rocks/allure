# frozen_string_literal: true

module ImportConnections
  # The provider refused the connection's tokens (PLAN_REMOTE_IMPORTS.md §7.3):
  # the tokens are wiped, the row turns `expired`, and the owner is told to
  # relink from the settings card. Imported data and preferences stay. A
  # session whose end is expected (Withings's day-long session, §7c.2) passes
  # `notify: false`: the card and the batch page say it, the bell stays
  # silent.
  class Expiry
    TOKEN_KEYS = %w[access_token refresh_token di_token di_refresh_token di_client_id
                    remember_cookie remember_cookie_name sessionid userid].freeze

    def initialize(connection, notify: true)
      @connection = connection
      @notify = notify
    end

    def call
      expired = @connection.with_lock do
        next false unless @connection.linked?

        @connection.update!(
          status: "expired",
          credentials: @connection.credentials.to_h.except(*TOKEN_KEYS),
          token_expires_at: nil,
          last_sync_error: message
        )
        true
      end
      return unless expired

      return unless @notify

      Notifications::Create.new(user: @connection.user, kind: "import_connection_expired", subject: @connection,
                                payload: { "provider" => @connection.provider }).call!
    end

    private

    # An expected end says why it happened when the provider has the words.
    def message
      generic = I18n.t("settings.connections.errors.expired")
      return generic if @notify

      I18n.t("settings.connections.#{@connection.provider}.errors.session_ended", default: generic)
    end
  end
end
