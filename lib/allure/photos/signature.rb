# frozen_string_literal: true

module Allure
  module Photos
    # The real type of an uploaded photo, read from its first bytes
    # (PLAN_PHOTOS.md §3.1). The declared content type and the extension are
    # never trusted. Answers nil for anything else, a GIF included.
    module Signature
      PNG = "\x89PNG\r\n\x1a\n".b
      JPEG = "\xFF\xD8\xFF".b
      HEIF_BRANDS = %w[heic heix hevc heim heis hevm hevs mif1 msf1].freeze
      EXTENSIONS = {
        "image/jpeg" => ".jpg",
        "image/png" => ".png",
        "image/webp" => ".webp",
        "image/heic" => ".heic"
      }.freeze

      module_function

      def detect(body)
        body = body.to_s.b
        return "image/jpeg" if body.start_with?(JPEG)
        return "image/png" if body.start_with?(PNG)
        return "image/webp" if body.bytesize > 12 && body[0, 4] == "RIFF" && body[8, 4] == "WEBP"
        return "image/heic" if body.bytesize > 12 && body[4, 4] == "ftyp" && HEIF_BRANDS.include?(body[8, 4])

        nil
      end

      def extension(content_type) = EXTENSIONS.fetch(content_type, ".bin")
    end
  end
end
