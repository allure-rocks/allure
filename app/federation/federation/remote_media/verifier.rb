# frozen_string_literal: true

require "stringio"

module Federation
  module RemoteMedia
    # Verifies fetched bytes against the declared attachment kind before any of
    # them are cached or parsed (docs/dev/FEDERATION.md). The GPX path returns the
    # already-parsed track so the pipeline never parses twice.
    class Verifier
      class InvalidContent < StandardError; end

      MAX_IMAGE_BYTES = 5.megabytes
      MAX_IMAGE_PIXELS = 40_000_000
      MAX_IMAGE_DIMENSION = 10_000
      MAX_GPX_BYTES = 10.megabytes
      MAX_GPX_POINTS = 50_000
      MAX_GPX_SEGMENTS = 500
      PNG_SIGNATURE = "\x89PNG\r\n\x1a\n".b

      Verified = Data.define(:content_type, :byte_size, :track)

      def initialize(kind:)
        @kind = kind
      end

      def call(body)
        @kind == "gpx" ? verify_gpx(body) : verify_image(body)
      end

      private

      def verify_image(body)
        raise InvalidContent, "image is too large" if body.bytesize > MAX_IMAGE_BYTES
        raise InvalidContent, "image is not a PNG" unless body.start_with?(PNG_SIGNATURE)

        image = Vips::Image.new_from_buffer(body, "")
        if image.width > MAX_IMAGE_DIMENSION || image.height > MAX_IMAGE_DIMENSION ||
           image.width * image.height > MAX_IMAGE_PIXELS
          raise InvalidContent, "image dimensions are too large"
        end

        Verified.new(content_type: "image/png", byte_size: body.bytesize, track: nil)
      rescue Vips::Error
        raise InvalidContent, "image cannot be decoded"
      end

      def verify_gpx(body)
        raise InvalidContent, "GPX is too large" if body.bytesize > MAX_GPX_BYTES

        # Allure's sanitized publication GPX omits timestamps and sensor
        # extensions by contract, so the remote parser accepts geometry-only.
        track = Allure::Gpx::Parser.new(max_points: MAX_GPX_POINTS, require_timestamps: false).parse(StringIO.new(body))
        raise InvalidContent, "too many recording segments" if track.segments.length > MAX_GPX_SEGMENTS

        Verified.new(content_type: "application/xml+gpx", byte_size: body.bytesize, track:)
      rescue Allure::Gpx::Error => error
        raise InvalidContent, error.message
      end
    end
  end
end
