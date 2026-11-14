# frozen_string_literal: true

module Allure
  module Photos
    # Reads the capture time and position of a photo from the EXIF fields
    # libvips exposes (PLAN_PHOTOS.md §3.2). Each value is a string such as
    # "45/1 10/1 3045/100 (45, 10, 30.45, Rational, 3 components, 24 bytes)":
    # only the part before the parenthesis is parsed. A malformed or missing
    # value yields nil for that fact, never an error.
    module Exif
      Result = Data.define(:taken_at_local, :utc_offset, :latitude, :longitude) do
        def position? = !latitude.nil? && !longitude.nil?
      end

      TIME_FIELDS = %w[exif-ifd2-DateTimeOriginal exif-ifd2-DateTimeDigitized exif-ifd0-DateTime].freeze
      OFFSET_FIELDS = %w[exif-ifd2-OffsetTimeOriginal exif-ifd2-OffsetTimeDigitized exif-ifd2-OffsetTime].freeze
      TIME_PATTERN = /\A(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})/
      OFFSET_PATTERN = /\A([+-])(\d{2}):(\d{2})\z/
      MAX_OFFSET = 14 * 3600

      module_function

      def parse(fields)
        fields = fields.to_h
        latitude = coordinate(fields, "GPSLatitude", "S", 90)
        longitude = coordinate(fields, "GPSLongitude", "W", 180)
        # Many cameras write 0/0 while they have no fix.
        latitude = longitude = nil if latitude.nil? || longitude.nil? || (latitude.zero? && longitude.zero?)

        Result.new(
          taken_at_local: local_time(fields),
          utc_offset: utc_offset(fields),
          latitude:,
          longitude:
        )
      end

      # The camera's wall clock, kept as a UTC value with the same digits: it
      # names no instant until an offset or a zone is applied.
      def local_time(fields)
        TIME_FIELDS.each do |name|
          match = TIME_PATTERN.match(value(fields[name]))
          next unless match

          parts = match.captures.map(&:to_i)
          next if parts[0] < 1900

          return Time.utc(*parts)
        rescue ArgumentError
          next
        end
        nil
      end

      def utc_offset(fields)
        OFFSET_FIELDS.each do |name|
          match = OFFSET_PATTERN.match(value(fields[name]))
          next unless match

          seconds = (match[2].to_i * 3600) + (match[3].to_i * 60)
          next if seconds > MAX_OFFSET

          return match[1] == "-" ? -seconds : seconds
        end
        nil
      end

      def coordinate(fields, name, negative_ref, limit)
        parts = value(fields["exif-ifd3-#{name}"]).split
        return if parts.length != 3

        degrees, minutes, seconds = parts.map { rational(it) }
        return if [ degrees, minutes, seconds ].any?(&:nil?)

        decimal = degrees + (minutes / 60.0) + (seconds / 3600.0)
        decimal = -decimal if value(fields["exif-ifd3-#{name}Ref"]).upcase.start_with?(negative_ref)
        decimal.finite? && decimal.abs <= limit ? decimal : nil
      end

      def rational(text)
        numerator, denominator = text.split("/", 2)
        numerator = Float(numerator, exception: false)
        denominator = denominator.nil? ? 1.0 : Float(denominator, exception: false)
        return if numerator.nil? || denominator.nil? || denominator.zero? || numerator.negative?

        numerator / denominator
      end

      def value(raw)
        raw.to_s.split(" (", 2).first.to_s.strip
      end
    end
  end
end
