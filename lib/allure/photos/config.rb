# frozen_string_literal: true

require "vips"

module Allure
  module Photos
    # Environment-driven configuration for workout photos (PLAN_PHOTOS.md §2.2,
    # §3). Values are read at call time. Photos are on unless `PHOTOS_ENABLED`
    # turns them off; `PHOTOS_QUOTA_MB` is the default storage quota of every
    # account, which the operator may override per account.
    module Config
      FALSE_VALUES = %w[0 false no off].freeze
      DEFAULT_QUOTA_MB = 2048
      MEGABYTE = 1024 * 1024

      MAX_BYTES = 20 * MEGABYTE
      MAX_PER_WORKOUT = 20
      MAX_DIMENSION = 12_000
      MAX_PIXELS = 100_000_000
      MAX_CAPTION = 500
      DISPLAY_SIZE = 2048
      THUMBNAIL_SIZE = 480
      PUBLICATION_SIZE = 1600
      WEBP_QUALITY = 82

      module_function

      def enabled? = !FALSE_VALUES.include?(ENV["PHOTOS_ENABLED"].to_s.strip.downcase)

      def default_quota_bytes
        value = Integer(ENV["PHOTOS_QUOTA_MB"].to_s.strip, exception: false)
        (value && value >= 0 ? value : DEFAULT_QUOTA_MB) * MEGABYTE
      end

      def max_megabytes = MAX_BYTES / MEGABYTE

      # HEIC needs a libvips built with libheif; the image may lack it.
      def heic_supported?
        return @heic_supported if defined?(@heic_supported)

        @heic_supported = Vips.get_suffixes.include?(".heic")
      rescue StandardError
        @heic_supported = false
      end

      def content_types
        types = %w[image/jpeg image/png image/webp]
        heic_supported? ? types + %w[image/heic] : types
      end
    end
  end
end
