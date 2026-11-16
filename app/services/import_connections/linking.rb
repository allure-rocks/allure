# frozen_string_literal: true

module ImportConnections
  # The request side of linking a provider with the account's own password
  # (docs/dev/REMOTE-IMPORTS.md for Garmin Connect, §7b.2 for EXR, §7c.2 for
  # Withings). Sign-in
  # is slow and Garmin's may stop for a verification code, so it runs in the
  # provider's link job; the password and, later, the code wait for it in the
  # connection's encrypted credentials for at most
  # `ImportConnection::PENDING_LIFETIME` — never as a job argument.
  class Linking
    class NotAllowed < StandardError; end

    PENDING_KEYS = %w[pending_email pending_password pending_mfa_code mfa_state mfa_method return_status].freeze
    LINK_JOBS = {
      "garmin_connect" => "ImportConnections::GarminConnect::LinkJob",
      "exr" => "ImportConnections::Exr::LinkJob",
      "withings" => "ImportConnections::Withings::LinkJob",
      "zwift" => "ImportConnections::Zwift::LinkJob"
    }.freeze

    def self.supported?(provider) = LINK_JOBS.key?(provider.to_s)

    def initialize(connection)
      @connection = connection
    end

    def start!(email:, password:, region: nil)
      raise NotAllowed if email.blank? || password.blank? || !self.class.supported?(@connection.provider)

      @connection.save! if @connection.new_record?
      @connection.with_lock do
        expire_stale!
        raise NotAllowed if @connection.linked? || @connection.pending? || @connection.unlinking?

        @connection.update!(
          status: "pending",
          region: ImportConnection::REGIONS.include?(region.to_s) ? region.to_s : "com",
          pending_expires_at: ImportConnection::PENDING_LIFETIME.from_now,
          last_sync_error: nil,
          credentials: {
            "pending_email" => email.to_s.strip,
            "pending_password" => password.to_s,
            "return_status" => @connection.status
          }
        )
      end
      link_job.perform_later(@connection)
    end

    def submit_code!(code)
      code = code.to_s.gsub(/\s+/, "")
      raise NotAllowed if code.empty?

      @connection.with_lock do
        expire_stale!
        raise NotAllowed unless @connection.status == "mfa_pending"

        @connection.update!(credentials: @connection.credentials.to_h.merge("pending_mfa_code" => code),
                            last_sync_error: nil)
      end
      link_job.perform_later(@connection)
    end

    def cancel!
      @connection.with_lock do
        reset!(nil) if @connection.pending?
      end
    end

    # A link attempt left behind (its job never ran, or the owner went away
    # during the verification) is undone the next time anyone looks.
    def expire_stale!
      reset!("expired_attempt") if @connection.persisted? && @connection.pending_expired?
    end

    def verifying? = @connection.credential(:pending_mfa_code).present?

    def reset!(reason)
      status = @connection.credential(:return_status).presence || "unlinked"
      status = "unlinked" unless ImportConnection::STATUSES.include?(status) && !ImportConnection::PENDING_STATUSES.include?(status)
      @connection.update!(
        status:,
        pending_expires_at: nil,
        credentials: @connection.credentials.to_h.except(*PENDING_KEYS),
        last_sync_error: reason && I18n.t("settings.connections.#{@connection.provider}.errors.#{reason}")
      )
    end

    private

    def link_job = LINK_JOBS.fetch(@connection.provider).constantize
  end
end
