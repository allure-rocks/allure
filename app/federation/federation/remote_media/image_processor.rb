# frozen_string_literal: true

require "digest"
require "stringio"

module Federation
  module RemoteMedia
    # Caches the verified route image as the card image. The remote PNG is
    # never re-rendered, and no remote URL is ever served to the browser.
    class ImageProcessor
      def initialize(attachment:, body:, verified:, now: Time.current)
        @attachment = attachment
        @body = body
        @verified = verified
        @now = now
      end

      def call
        blob = nil
        begin
          blob = ActiveStorage::Blob.create_and_upload!(
            io: StringIO.new(@body),
            filename: "#{@attachment.filename_stem}.png",
            content_type: @verified.content_type,
            identify: false
          )
          @attachment.update!(
            status: "cached",
            blob_id: blob.id,
            content_digest: Digest::SHA256.hexdigest(@body),
            byte_size: @verified.byte_size,
            fetched_at: @now,
            last_error: nil
          )
          @attachment
        rescue StandardError
          blob&.purge
          raise
        end
      end
    end
  end
end
