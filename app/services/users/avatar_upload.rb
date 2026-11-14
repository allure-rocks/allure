# frozen_string_literal: true

require "image_processing/vips"

module Users
  # Normalizes an avatar upload (DESIGN.md §9.4): validates the real format and
  # dimensions from the bytes, decodes the image reduced, keeps the square the
  # account chose — or the centred one — strips metadata and attaches a
  # normalized WebP. The original upload is never stored or served, a malformed
  # image leaves the previous avatar untouched, and the replaced blob is
  # purged.
  class AvatarUpload
    class Invalid < StandardError; end

    MAX_BYTES = 20.megabytes
    MAX_MEGABYTES = 20
    MAX_DIMENSION = 8192
    # A phone photo is decoded straight to this long side (libvips shrinks it
    # while decoding), so a 24 or 48 megapixel upload costs what a 4096 px one
    # used to, and a tight crop still has enough pixels for the 512 px avatar.
    DECODE_SIZE = 4096
    OUTPUT_SIZE = 512
    OUTPUT_CONTENT_TYPE = "image/webp"
    OUTPUT_FILENAME = "avatar.webp"
    ALLOWED_TYPES = %w[image/jpeg image/png image/webp].freeze
    IMAGE_SIGNATURES = {
      "\x89PNG\r\n\x1a\n".b => "image/png",
      "\xFF\xD8\xFF".b => "image/jpeg"
    }.freeze

    def initialize(user:)
      @user = user
    end

    def call(file, crop: nil)
      body = read_bytes(file)
      validate_size!(body)
      validate_type!(body)
      validate_dimensions!(open_body!(body))
      image = decode(body)
      replace(normalize(image, Allure::Avatar::Crop.region(image:, placement: crop)))
    end

    private

    def read_bytes(file)
      io = file.respond_to?(:tempfile) ? file.tempfile : file
      io.rewind if io.respond_to?(:rewind)
      io.read.to_s.b
    end

    def validate_size!(body)
      raise Invalid, message(:missing) if body.empty?
      raise Invalid, message(:too_large, max: MAX_MEGABYTES) if body.bytesize > MAX_BYTES
    end

    def validate_type!(body)
      return if detect_type(body)

      raise Invalid, message(:unsupported_type)
    end

    def detect_type(body)
      IMAGE_SIGNATURES.each { |signature, type| return type if body.start_with?(signature) }
      "image/webp" if body.bytesize > 12 && body[0, 4] == "RIFF" && body[8, 4] == "WEBP"
    end

    # The header alone: a file that announces enormous dimensions is refused
    # before anything decodes it.
    def open_body!(body)
      Vips::Image.new_from_buffer(body, "")
    rescue Vips::Error
      raise Invalid, message(:unreadable)
    end

    def validate_dimensions!(image)
      return if image.width <= MAX_DIMENSION && image.height <= MAX_DIMENSION

      raise Invalid, message(:too_large_dimensions, max: MAX_DIMENSION)
    end

    # thumbnail_buffer applies the EXIF orientation (its `no-rotate` default is
    # off) and never enlarges, so the crop coordinates the browser sent
    # (oriented pixels) land on the same picture.
    def decode(body)
      Vips::Image.thumbnail_buffer(body, DECODE_SIZE, size: :down)
    rescue Vips::Error
      raise Invalid, message(:unreadable)
    end

    # image_processing 2 no longer sharpens after a resize; `sharpen: true`
    # applies the mask 1.x used, so avatars keep the same rendering.
    def normalize(image, region)
      source = region ? image.crop(region[:left], region[:top], region[:size], region[:size]) : image
      ImageProcessing::Vips
        .source(source)
        .resize_to_fill(OUTPUT_SIZE, OUTPUT_SIZE, sharpen: true)
        .convert("webp")
        .saver(strip: true)
        .call
    rescue Vips::Error, ImageProcessing::Error
      raise Invalid, message(:unreadable)
    end

    def replace(output)
      previous_blob = @user.avatar.blob if @user.avatar.attached?
      @user.avatar.attach(io: output, filename: OUTPUT_FILENAME, content_type: OUTPUT_CONTENT_TYPE, identify: false)
      previous_blob&.purge_later
    end

    def message(key, **options)
      I18n.t("settings.profile.avatar_errors.#{key}", **options)
    end
  end
end
