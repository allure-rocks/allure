# frozen_string_literal: true

require "image_processing/vips"

module Allure
  module Photos
    # Only the derivatives leave this processor. Metadata is removed at the
    # encoder, not by a best-effort EXIF blacklist; originals are untouched.
    class Processor
      class Invalid < StandardError
        attr_reader :code

        def initialize(code)
          @code = code
          super(code)
        end
      end

      def self.call(path)
        image = Vips::Image.new_from_file(path, fail_on: :warning)
        raise Invalid, "too_large_dimensions" if image.width > Config::MAX_DIMENSION || image.height > Config::MAX_DIMENSION ||
                                                image.width * image.height > Config::MAX_PIXELS
        raise Invalid, "unreadable" if image.get_typeof("n-pages").positive? && image.get("n-pages") > 1

        # Capture time and position are read before stripping, for the
        # owner's placement only (PLAN_PHOTOS.md §3.2).
        exif = Exif.parse(exif_fields(image))
        image = image.autorot
        display = render(image, Config::DISPLAY_SIZE)
        thumbnail = render(image, Config::THUMBNAIL_SIZE)
        yield display, thumbnail, image.width, image.height, exif
      rescue Vips::Error, ImageProcessing::Error
        raise Invalid, "unreadable"
      ensure
        display&.close!
        thumbnail&.close!
      end

      Copies = Data.define(:display, :thumbnail, :width, :height)

      # A publication's own copies (PLAN_PHOTOS.md §5.3), from an already
      # stripped display file: bounded again and encoded without metadata.
      # The caller closes both tempfiles.
      def self.publication_copies(path)
        image = Vips::Image.new_from_file(path, fail_on: :warning)
        display = render(image, Config::PUBLICATION_SIZE)
        begin
          thumbnail = render(image, Config::THUMBNAIL_SIZE)
        rescue StandardError
          display.close!
          raise
        end
        measured = Vips::Image.new_from_file(display.path)
        Copies.new(display:, thumbnail:, width: measured.width, height: measured.height)
      rescue Vips::Error, ImageProcessing::Error
        raise Invalid, "unreadable"
      end

      # The size a publication copy of a width × height photo takes, for a
      # preview that makes no copy.
      def self.bounded_size(width, height)
        scale = [ Config::PUBLICATION_SIZE.to_f / [ width, height ].max, 1.0 ].min
        [ [ (width * scale).round, 1 ].max, [ (height * scale).round, 1 ].max ]
      end

      def self.render(image, size)
        ImageProcessing::Vips.source(image).resize_to_limit(size, size, sharpen: true)
          .convert("webp").saver(strip: true, Q: Config::WEBP_QUALITY).call
      end

      def self.exif_fields(image)
        image.get_fields.grep(/\Aexif-ifd/).to_h { [ it, image.get(it).to_s ] }
      rescue Vips::Error
        {}
      end
      private_class_method :render, :exif_fields
    end
  end
end
