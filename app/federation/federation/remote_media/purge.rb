# frozen_string_literal: true

module Federation
  module RemoteMedia
    # Removes cached media and location-bearing representation once a received
    # object is deleted or no entitlement remains. Idempotent; the tombstone
    # and its non-geographic audit fields survive.
    class Purge
      def initialize(owner:, now: Time.current)
        @owner = owner
        @now = now
      end

      def call!(force: false)
        return @owner unless force || purgeable?

        @owner.attachments.find_each do |attachment|
          blob = attachment.blob
          unless attachment.status == "purged"
            # The descriptor's foreign key must be released before the blob can
            # be destroyed; Blob#purge swallows the resulting FK error.
            attachment.update!(
              status: "purged",
              purged_at: @now,
              blob_id: nil,
              content_digest: nil,
              byte_size: nil,
              next_attempt_at: nil,
              last_error: nil
            )
          end
          purge_blob(blob)
        end

        @owner.redact_location!(at: @now)
        @owner
      end

      private

      # Media is retained while at least one local account is still entitled.
      # A public object keeps its cached media through withdrawal, because any
      # signed-in account may still open it; only a deleted object or a
      # followers-only object whose last entitlement went away is purged.
      # Author deletion is the author's own withdrawal and forces the purge.
      def purgeable?
        @owner.deleted? || (@owner.audience == "followers" && @owner.recipients.active.none?)
      end

      def purge_blob(blob)
        blob&.purge
      rescue StandardError => error
        Rails.error.report(error, handled: true, context: { component: self.class.name, blob_id: blob.id })
      end
    end
  end
end
