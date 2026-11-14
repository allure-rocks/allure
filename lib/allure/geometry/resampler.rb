# frozen_string_literal: true

module Allure
  module Geometry
    module Resampler
      module_function

      def resample(coordinates, count: nil, spacing: nil)
        points = normalize_coordinates(coordinates)
        raise ArgumentError, "exactly one sampling mode is required" if count.nil? == spacing.nil?

        lengths = cumulative_lengths(points)
        length = lengths.last
        if count
          numeric_count = Float(count)
          raise ArgumentError, "count must be an integer" unless numeric_count.finite? && numeric_count == numeric_count.to_i

          count = numeric_count.to_i
          raise ArgumentError, "count must be at least two" if count < 2

          interval = length / (count - 1).to_f
          targets = Array.new(count) { |index| interval * index }
        else
          spacing = Float(spacing)
          raise ArgumentError, "spacing must be positive" unless spacing.finite? && spacing.positive?

          targets = if length.zero?
            [ 0.0, length ]
          else
            (0...((length / spacing).floor + 1)).map { |index| index * spacing }
          end
          targets << length unless targets.last == length
        end

        # Targets never decrease, so one cursor walks the cumulative lengths
        # once for the whole series instead of searching them per target.
        index = 1
        targets.map do |target|
          index += 1 while index < lengths.length && lengths[index] < target
          point_at_cumulative_distance(points, lengths, target, index)
        end.tap(&:freeze)
      rescue TypeError, ArgumentError => error
        raise error if error.message.match?(/count|spacing|sampling mode|coordinates|coordinate|polyline/)

        raise ArgumentError, "invalid resampling options", cause: error
      end

      def normalize_coordinates(coordinates)
        points = Array(coordinates).map { |coordinate| normalize_coordinate(coordinate) }
        raise ArgumentError, "polyline requires at least two coordinates" if points.length < 2

        points
      rescue TypeError, ArgumentError => error
        raise error if error.message.match?(/polyline|coordinate/)

        raise ArgumentError, "invalid coordinates", cause: error
      end

      def normalize_coordinate(coordinate)
        values = Array(coordinate)
        raise ArgumentError, "invalid coordinate" unless values.length == 2

        longitude, latitude = values
        longitude = Float(longitude)
        latitude = Float(latitude)
        unless longitude.finite? && latitude.finite? && longitude.between?(-180, 180) && latitude.between?(-90, 90)
          raise ArgumentError, "invalid coordinate"
        end

        [ longitude, latitude ].freeze
      rescue TypeError, ArgumentError
        raise ArgumentError, "invalid coordinate"
      end

      def cumulative_lengths(points)
        lengths = [ 0.0 ]
        points.each_cons(2) do |first, second|
          lengths << lengths.last + horizontal_distance(first, second)
        end
        lengths
      end

      def total_length(points)
        cumulative_lengths(points).last
      end

      def point_at_distance(points, target)
        lengths = cumulative_lengths(points)
        index = lengths.index { |length| length >= target }
        point_at_cumulative_distance(points, lengths, target, index)
      end

      # `index` is the first cumulative length at or beyond `target` (nil when
      # none is), which the caller already knows when it walks the lengths.
      def point_at_cumulative_distance(points, lengths, target, index)
        total = lengths.last
        return points.first.dup.freeze if total.zero?
        return points.last.dup.freeze if target >= total
        return points.first.dup.freeze if target <= 0

        index = 1 if index.nil? || index.zero? || index >= lengths.length
        previous_length = lengths[index - 1]
        edge_length = lengths[index] - previous_length

        if edge_length.zero?
          points[index].dup.freeze
        else
          fraction = (target - previous_length) / edge_length
          interpolate(points[index - 1], points[index], fraction)
        end
      end

      def interpolate(first, second, fraction)
        longitude_delta = Allure::Gpx::Geo.normalize_longitude_delta(second[0] - first[0])
        longitude = first[0] + (longitude_delta * fraction)
        longitude -= 360.0 while longitude > 180.0
        longitude += 360.0 while longitude < -180.0

        [ longitude, first[1] + ((second[1] - first[1]) * fraction) ].freeze
      end

      def horizontal_distance(first, second)
        Allure::Gpx::Geo.horizontal_distance(first[1], first[0], second[1], second[0])
      end
    end
  end
end
