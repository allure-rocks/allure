# frozen_string_literal: true

module Allure
  module Geometry
    module Frechet
      DEFAULT_BAND = 0.10

      module_function

      # With a ceiling, distances above it are saturated at ceiling + 1. This
      # preserves the verdict and every accepted distance, while unreachable
      # DP cells need no geodesic calculation. Infinity still means no band path
      # and therefore retains the existing full-matrix fallback.
      def distance(reference, candidate, band: DEFAULT_BAND, ceiling: nil)
        first = normalize_coordinates(reference)
        second = normalize_coordinates(candidate)
        band = validate_band(band)
        ceiling = validate_ceiling(ceiling)

        return dynamic_distance(first, second, band: nil, ceiling:) if band.nil? || band >= 1.0

        banded = dynamic_distance(first, second, band:, ceiling:)
        banded.finite? ? banded : dynamic_distance(first, second, band: nil, ceiling:)
      end

      def normalize_coordinates(coordinates)
        points = Array(coordinates).map do |coordinate|
          values = Array(coordinate)
          raise ArgumentError, "invalid coordinate" unless values.length == 2

          longitude, latitude = values
          longitude = Float(longitude)
          latitude = Float(latitude)
          unless longitude.finite? && latitude.finite? && longitude.between?(-180, 180) && latitude.between?(-90, 90)
            raise ArgumentError, "invalid coordinate"
          end

          [ longitude, latitude ]
        end
        raise ArgumentError, "curves require at least one coordinate" if points.empty?

        points
      rescue TypeError, ArgumentError => error
        raise error if error.message.match?(/coordinate|curves/)

        raise ArgumentError, "invalid curve", cause: error
      end

      def validate_band(band)
        return if band.nil?

        value = Float(band)
        raise ArgumentError, "band must be between zero and one" unless value.finite? && value.between?(0, 1)

        value
      rescue TypeError, ArgumentError => error
        raise error if error.message.include?("band")

        raise ArgumentError, "invalid band", cause: error
      end

      def validate_ceiling(ceiling)
        return if ceiling.nil?

        value = Float(ceiling)
        raise ArgumentError, "ceiling must be non-negative and finite" unless value.finite? && value >= 0

        value
      end

      # The discrete Fréchet recurrence needs only the previous row, and a
      # banded run only visits the cells of the band: two long loops compare in
      # O(n × band × m) time and O(m) memory instead of a full n × m matrix.
      # Cells outside the band stay infinite, exactly as if they were skipped.
      def dynamic_distance(first, second, band:, ceiling: nil)
        return bounded_dynamic_distance(first, second, band:, ceiling:) if ceiling

        first_count = first.length
        second_count = second.length
        previous = nil

        first_count.times do |first_index|
          current = Array.new(second_count, Float::INFINITY)
          low, high = band_columns(first_index, first_count, second_count, band)
          (low..high).each do |second_index|
            cell_distance = horizontal_distance(first[first_index], second[second_index])
            current[second_index] = if first_index.zero? && second_index.zero?
              cell_distance
            elsif first_index.zero?
              [ current[second_index - 1], cell_distance ].max
            elsif second_index.zero?
              [ previous[second_index], cell_distance ].max
            else
              [
                [
                  previous[second_index],
                  previous[second_index - 1],
                  current[second_index - 1]
                ].min,
                cell_distance
              ].max
            end
          end
          previous = current
        end

        previous.last
      end

      # Only cells reachable under the leash can contribute to an accepted
      # distance. Keep those cells sparsely and extend each row horizontally
      # while it remains reachable, instead of walking the whole progress band.
      def bounded_dynamic_distance(first, second, band:, ceiling:)
        return Float::INFINITY unless band_path?(first.length, second.length, band)

        previous = {}
        first.each_index do |row|
          low, high = band_columns(row, first.length, second.length, band)
          previous_low, previous_high = row.zero? ? [ 0, 0 ] : previous.keys.minmax
          column = [ low, previous_low ].max
          current = {}
          while column <= high && (column <= previous_high + 1 || current.key?(column - 1))
            predecessor = if row.zero? && column.zero?
              0.0
            else
              [ previous.fetch(column, Float::INFINITY),
                previous.fetch(column - 1, Float::INFINITY),
                current.fetch(column - 1, Float::INFINITY) ].min
            end
            if predecessor <= ceiling
              value = [ predecessor, horizontal_distance(first[row], second[column]) ].max
              current[column] = value if value <= ceiling
            end
            column += 1
          end
          return ceiling + 1 if current.empty?

          previous = current
        end
        previous.fetch(second.length - 1, ceiling + 1)
      end

      # Separate structural band failure from a distance refusal: only the
      # former must fall back to the full matrix, exactly like the uncapped DP.
      def band_path?(first_count, second_count, band)
        return true if band.nil?

        reachable_low = reachable_high = 0
        first_count.times do |row|
          low, high = band_columns(row, first_count, second_count, band)
          low = [ low, reachable_low ].max
          return false if low > high || low > reachable_high + 1

          reachable_low = low
          reachable_high = high
        end
        reachable_high == second_count - 1
      end

      # The columns of one row inside the band: every column without a band,
      # else the contiguous run of columns whose progress stays within `band`
      # of the row's. The arithmetic estimate is widened by a cell and trimmed
      # with the exact predicate, so rounding never moves the boundary.
      def band_columns(first_index, first_count, second_count, band)
        last_column = second_count - 1
        return [ 0, last_column ] if band.nil?

        first_progress = first_count == 1 ? 0.0 : first_index.fdiv(first_count - 1)
        low = (((first_progress - band) * last_column).floor - 1).clamp(0, last_column)
        high = (((first_progress + band) * last_column).ceil + 1).clamp(0, last_column)
        low += 1 while low < high && progress_difference(first_index, first_count, low, second_count) > band
        high -= 1 while high > low && progress_difference(first_index, first_count, high, second_count) > band
        return [ 1, 0 ] if progress_difference(first_index, first_count, low, second_count) > band

        [ low, high ]
      end

      def progress_difference(first_index, first_count, second_index, second_count)
        first_progress = first_count == 1 ? 0.0 : first_index.fdiv(first_count - 1)
        second_progress = second_count == 1 ? 0.0 : second_index.fdiv(second_count - 1)
        (first_progress - second_progress).abs
      end

      def horizontal_distance(first, second)
        Allure::Gpx::Geo.horizontal_distance(first[1], first[0], second[1], second[0])
      end
    end
  end
end
