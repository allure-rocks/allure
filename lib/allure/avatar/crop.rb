# frozen_string_literal: true

module Allure
  module Avatar
    # The square an account chose on its upload (DESIGN.md §9.4). The browser
    # measures the oriented image it displays and sends the square in whole
    # pixels of that image; the server crops the reduced copy it decoded, so
    # the placement is scaled here. Anything missing, malformed, or measured on
    # an image whose proportions differ (a browser that did not apply the EXIF
    # orientation) is ignored, and the centred square stands.
    class Crop
      TOLERANCE = 0.02
      KEYS = %i[x y size width height].freeze

      def self.region(image:, placement:)
        new(image:, placement:).region
      end

      def initialize(image:, placement:)
        @image = image
        @placement = placement.respond_to?(:to_h) ? placement.to_h.symbolize_keys : {}
      end

      def region
        return unless valid?

        size = scaled(@size).clamp(1, short_side)
        {
          left: scaled(@x).clamp(0, @image.width - size),
          top: scaled(@y).clamp(0, @image.height - size),
          size:
        }
      end

      private

      def valid?
        @x, @y, @size, @measured_width, @measured_height = KEYS.map { |key| number(key) }
        return false if [ @x, @y, @size, @measured_width, @measured_height ].any?(&:nil?)
        return false unless @size.positive? && @measured_width.positive? && @measured_height.positive?

        proportions_match?
      end

      def number(key)
        value = @placement[key]
        return unless value.is_a?(Numeric) || value.is_a?(String)

        number = Float(value, exception: false)
        number if number&.finite?
      end

      def proportions_match?
        measured = @measured_width / @measured_height
        decoded = @image.width.to_f / @image.height
        (measured - decoded).abs <= TOLERANCE * decoded
      end

      def scaled(value) = (value * scale).round
      def scale = @image.width / @measured_width
      def short_side = [ @image.width, @image.height ].min
    end
  end
end
