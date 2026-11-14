# frozen_string_literal: true

module ImportConnections
  # The operator's « Révoquer » (PLAN_REMOTE_IMPORTS.md §10): the connection
  # turns `revoked`, its credentials are wiped and its running batches are
  # cancelled; the imported workouts and equipment stay untouched. The owner
  # is told and may link again. The caller records the audit event.
  class OperatorRevocation
    REVOCABLE = %w[linked expired pending mfa_pending].freeze

    def initialize(connection)
      @connection = connection
    end

    def revocable? = REVOCABLE.include?(@connection.status)

    # True when the connection was revoked by this call.
    def call!
      revoked = @connection.with_lock do
        next false unless revocable?

        @connection.update!(
          status: "revoked",
          revoked_at: Time.current,
          credentials: {},
          token_expires_at: nil,
          pending_expires_at: nil,
          last_sync_error: I18n.t("settings.connections.errors.operator_revoked", locale: @connection.user.locale)
        )
        true
      end
      return false unless revoked

      @connection.import_batches.where(status: %w[queued processing]).find_each(&:cancel!)
      Notifications::Create.new(user: @connection.user, kind: "import_connection_revoked", subject: @connection,
                                payload: { "provider" => @connection.provider, "by" => "operator" }).call!
      true
    end
  end
end
