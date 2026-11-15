# frozen_string_literal: true

module Federation
  module Safety
    # The inbound admission rate limit (docs/dev/FEDERATION.md). Every admitted activity
    # counts, whatever its later status: the row itself is the evidence that the
    # authority spent capacity. Rejected and failed items still had to pass the
    # signature check and actor resolution, so they count too.
    module InboundRateLimiter
      PER_MINUTE = 60
      PER_HOUR = 600

      WINDOWS = [
        [ PER_MINUTE, 1.minute ],
        [ PER_HOUR, 1.hour ]
      ].freeze

      Result = Data.define(:allowed, :retry_after) do
        def allowed? = allowed
      end

      module_function

      def check(domain, now: Time.current)
        return Result.new(allowed: true, retry_after: nil) if domain.blank?

        WINDOWS.each do |limit, window|
          next if count_in_window(domain, now:, window:) < limit

          retry_after = seconds_until_free(domain, now:, window:)
          return Result.new(allowed: false, retry_after:)
        end
        Result.new(allowed: true, retry_after: nil)
      end

      def count_in_window(domain, now:, window:)
        FederationInboxItem.where(remote_domain: domain).where("created_at > ?", now - window).count
      end

      def seconds_until_free(domain, now:, window:)
        oldest = FederationInboxItem.where(remote_domain: domain).where("created_at > ?", now - window).minimum(:created_at)
        return window.to_i if oldest.blank?

        [ (oldest + window - now).ceil, 1 ].max
      end
    end
  end
end
