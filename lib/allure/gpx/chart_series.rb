# frozen_string_literal: true

module Allure
  module Gpx
    class ChartSeries
      MAX_POINTS = 1_000
      SERIES_KEYS = {
        elevation: PointSerializer::KEY_ELEVATION,
        speed: PointSerializer::KEY_SPEED,
        heart_rate: PointSerializer::KEY_HEART_RATE,
        cadence: PointSerializer::KEY_CADENCE,
        power: PointSerializer::KEY_POWER,
        device_temperature: PointSerializer::KEY_TEMPERATURE
      }.freeze

      # `extra_values` is an optional array of hashes aligned with the global
      # point order, merged into each point before bounding (the weather
      # channels, docs/dev/WEATHER.md).
      def initialize(workout_started_at: nil, segments: nil, points: nil, max_points: MAX_POINTS, include_index: false,
                     series: [ :elevation ], extra_values: nil)
        @workout_started_at = workout_started_at
        @segments = segments
        @points = points
        @max_points = max_points
        @include_index = include_index
        @series = Array(series).map(&:to_sym)
        @extra_values = extra_values
        unknown = @series - SERIES_KEYS.keys
        raise ArgumentError, "unknown chart series: #{unknown.join(', ')}" if unknown.any?
      end

      def call
        bound(@points || extract_points)
      end

      private

      def extract_points
        distance_offset = 0.0
        point_index = 0

        @segments.each_with_index.flat_map do |segment, segment_index|
          time_offset = (segment.started_at - @workout_started_at).round
          points = segment.points.map do |point|
            raw_time = point[PointSerializer::KEY_TIME]
            value = {
              distance: (distance_offset + point.fetch(PointSerializer::KEY_DISTANCE)).round(1),
              elapsed_time: raw_time && (time_offset + raw_time)
            }
            @series.each { |key| value[key] = point[SERIES_KEYS.fetch(key)] }
            value.merge!(@extra_values[point_index] || {}) if @extra_values
            if @include_index
              value[:index] = point_index
              value[:segment_index] = segment_index
            end
            point_index += 1
            value
          end
          distance_offset += segment.distance.to_f
          points
        end
      end

      def bound(points)
        return points if points.length <= @max_points

        mandatory = mandatory_indexes(points)
        mandatory = trim_mandatory(mandatory, points) if mandatory.length > @max_points
        selected = mandatory.to_h { [ it, true ] }
        remaining = @max_points - selected.length

        if remaining.positive?
          step = (points.length - 1).fdiv(remaining + 1)
          1.upto(remaining) do |rank|
            index = nearest_available_index((rank * step).round, selected, points.length)
            selected[index] = true if index
          end
        end

        index = 1
        while selected.length < @max_points && index < points.length - 1
          selected[index] = true
          index += 1
        end

        selected.keys.sort.map { points[it] }
      end

      def mandatory_indexes(points)
        extrema = @series.flat_map { |key| extrema_indexes(points, key) }
        gap_boundaries = @series.flat_map { |key| gap_boundary_indexes(points, key) }
        ([ 0, points.length - 1 ] + extrema + gap_boundaries).uniq.sort
      end

      def extrema_indexes(points, key)
        minimum = nil
        maximum = nil

        points.each_with_index do |point, index|
          value = point[key]
          next if value.nil?

          minimum = [ value, index ] if minimum.nil? || value < minimum.first
          maximum = [ value, index ] if maximum.nil? || value > maximum.first
        end

        [ minimum&.last, maximum&.last ].compact
      end

      def gap_boundary_indexes(points, key)
        points.each_index.filter do |index|
          index.positive? && points[index][key].nil? != points[index - 1][key].nil?
        end
      end

      def trim_mandatory(indexes, points)
        extrema = @series.flat_map { |key| extrema_indexes(points, key) }
        core = ([ 0, points.length - 1 ] + extrema).uniq
        optional = indexes - core
        core + evenly_sample(optional, @max_points - core.length)
      end

      def evenly_sample(indexes, count)
        return [] if count <= 0 || indexes.empty?
        return indexes if indexes.length <= count

        step = indexes.length.fdiv(count)
        count.times.map { indexes[(it * step).floor] }
      end

      def nearest_available_index(preferred, selected, point_count)
        return preferred unless selected[preferred]

        1.upto(point_count) do |offset|
          after = preferred + offset
          return after if after < point_count - 1 && !selected[after]

          before = preferred - offset
          return before if before.positive? && !selected[before]
        end

        nil
      end
    end
  end
end
