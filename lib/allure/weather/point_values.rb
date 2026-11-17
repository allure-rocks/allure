# frozen_string_literal: true

module Allure
  module Weather
    # The weather read at every recorded point, for the profile chart
    # (docs/dev/WEATHER.md): the air temperature interpolated in time from the
    # series, and the effective headwind of the ~100 m stretch the point
    # belongs to (positive against, negative behind; nil while stopped).
    # Returns one `{ temperature:, headwind: }` per input point, aligned.
    class PointValues
      def initialize(points:, rows:, stopped_speed_threshold_mps: 0.0)
        @points = Array(points)
        @rows = Array(rows).select(&:usable?).sort_by(&:time)
        @threshold = stopped_speed_threshold_mps.to_f
      end

      def call
        return Array.new(@points.length) { { temperature: nil, headwind: nil } } if @rows.empty?

        headwinds = stretch_headwinds
        @points.each_with_index.map do |point, index|
          { temperature: temperature_at(point.time.to_f)&.round(1), headwind: headwinds[index]&.round(2) }
        end
      end

      private

      # Points arrive in time order, so the bracketing row only moves forward.
      def row_index(time)
        @cursor ||= 0
        @cursor = 0 if @rows[@cursor].time > time
        @cursor += 1 while @cursor + 1 < @rows.length && @rows[@cursor + 1].time <= time
        @cursor
      end

      def temperature_at(time)
        index = row_index(time)
        before = @rows[index]
        after = @rows[[ index + 1, @rows.length - 1 ].min]
        span = after.time - before.time
        return before.temperature unless span.positive?

        fraction = ((time - before.time) / span).clamp(0.0, 1.0)
        before.temperature + (after.temperature - before.temperature) * fraction
      end

      # Every point of a moving stretch carries that stretch's component.
      def stretch_headwinds
        values = Array.new(@points.length)
        anchor_index = nil
        @points.each_with_index do |point, index|
          next if point.latitude.nil? || point.longitude.nil?

          if anchor_index.nil? || point.segment_index != @points[anchor_index].segment_index
            anchor_index = index
          elsif point.distance - @points[anchor_index].distance >= WindExposure::STRETCH_METRES
            assign(values, anchor_index, index)
            anchor_index = index
          end
        end
        values
      end

      def assign(values, from_index, to_index)
        from = @points[from_index]
        to = @points[to_index]
        duration = to.time - from.time
        metres = to.distance - from.distance
        return unless duration.positive? && metres.positive? && metres / duration >= @threshold

        speed, origin = wind_at(from.time.to_f + duration / 2.0)
        return if origin.nil?

        bearing = Wind.bearing(from.latitude, from.longitude, to.latitude, to.longitude)
        component = Wind.headwind(speed, origin, bearing)
        (from_index..to_index).each { |index| values[index] = component }
      end

      def wind_at(time)
        index = row_index(time)
        before = @rows[index]
        after = @rows[[ index + 1, @rows.length - 1 ].min]
        span = after.time - before.time
        fraction = span.positive? ? ((time - before.time) / span).clamp(0.0, 1.0) : 0.0
        speed = before.wind_speed + (after.wind_speed - before.wind_speed) * fraction
        u1, v1 = Wind.components(before.wind_speed, before.wind_direction)
        u2, v2 = Wind.components(after.wind_speed, after.wind_direction)
        [ speed, Wind.direction(u1 + (u2 - u1) * fraction, v1 + (v2 - v1) * fraction) ]
      end
    end
  end
end
