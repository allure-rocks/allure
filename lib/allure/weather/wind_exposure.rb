# frozen_string_literal: true

module Allure
  module Weather
    # The wind the athlete actually faced (docs/dev/WEATHER.md). The moving
    # track is cut into ~100 m stretches inside each recording segment; each
    # stretch's bearing is compared with the 10 m wind at its mid-time, and its
    # distance is counted head (origin within ±45° of ahead), tail (within ±45°
    # of behind) or cross. The mean effective headwind is the distance-weighted
    # wind component against travel: positive against, negative behind.
    #
    # Stopped stretches (below the sport's stopped speed) count nowhere. The
    # pass is linear in points. `ranges` (pairs of cumulative distances in
    # metres) optionally returns the same figures per range, for the splits.
    class WindExposure
      STRETCH_METRES = 100.0
      MIN_TAIL_METRES = 20.0

      Result = Data.define(:distance, :head, :tail, :cross, :headwind) do
        def self.empty = new(distance: 0.0, head: 0.0, tail: 0.0, cross: 0.0, headwind: nil)

        def self.from_h(hash)
          hash = hash.to_h
          new(distance: hash["distance"].to_f, head: hash["head"].to_f, tail: hash["tail"].to_f,
              cross: hash["cross"].to_f, headwind: hash["headwind"]&.to_f)
        end

        def present? = distance.positive?

        def to_h
          { "distance" => distance.round(1), "head" => head.round(3), "tail" => tail.round(3),
            "cross" => cross.round(3), "headwind" => headwind&.round(2) }
        end
      end

      Accumulator = Struct.new(:distance, :head, :tail, :cross, :weighted) do
        def self.blank = new(0.0, 0.0, 0.0, 0.0, 0.0)

        def add(sector, metres, headwind)
          self.distance += metres
          self[sector] += metres
          self.weighted += headwind * metres
        end

        def result
          return Result.empty unless distance.positive?

          Result.new(distance:, head: head / distance, tail: tail / distance, cross: cross / distance,
                     headwind: weighted / distance)
        end
      end

      def initialize(points:, rows:, stopped_speed_threshold_mps: 0.0, ranges: [])
        @points = Array(points).select { |point| !point.latitude.nil? && !point.longitude.nil? }
        @rows = Array(rows).select(&:usable?).sort_by(&:time)
        @threshold = stopped_speed_threshold_mps.to_f
        @ranges = Array(ranges)
      end

      def call
        total = Accumulator.blank
        per_range = Array.new(@ranges.length) { Accumulator.blank }
        return [ total.result, per_range.map(&:result) ] if @rows.empty? || @points.length < 2

        each_stretch do |from, to|
          metres = to.distance - from.distance
          duration = to.time - from.time
          next unless duration.positive? && metres.positive?
          next if metres / duration < @threshold

          wind = wind_at(from.time.to_f + duration / 2.0)
          next if wind.nil?

          speed, origin = wind
          bearing = Wind.bearing(from.latitude, from.longitude, to.latitude, to.longitude)
          sector = Wind.sector(origin, bearing)
          headwind = Wind.headwind(speed, origin, bearing)
          total.add(sector, metres, headwind)
          index = range_index(from.distance + metres / 2.0)
          per_range[index].add(sector, metres, headwind) if index
        end

        [ total.result, per_range.map(&:result) ]
      end

      private

      def each_stretch
        anchor = nil
        previous = nil
        @points.each do |point|
          if anchor.nil? || point.segment_index != anchor.segment_index
            yield anchor, previous if anchor && previous && previous.distance - anchor.distance >= MIN_TAIL_METRES
            anchor = point
          elsif point.distance - anchor.distance >= STRETCH_METRES
            yield anchor, point
            anchor = point
          end
          previous = point
        end
        yield anchor, previous if anchor && previous && previous.distance - anchor.distance >= MIN_TAIL_METRES
      end

      def wind_at(time)
        index = @rows.rindex { |row| row.time <= time } || 0
        before = @rows[index]
        after = @rows[[ index + 1, @rows.length - 1 ].min]
        span = after.time - before.time
        fraction = span.positive? ? ((time - before.time) / span).clamp(0.0, 1.0) : 0.0
        speed = before.wind_speed + (after.wind_speed - before.wind_speed) * fraction
        u1, v1 = Wind.components(before.wind_speed, before.wind_direction)
        u2, v2 = Wind.components(after.wind_speed, after.wind_direction)
        origin = Wind.direction(u1 + (u2 - u1) * fraction, v1 + (v2 - v1) * fraction)
        origin.nil? ? nil : [ speed, origin ]
      end

      def range_index(distance)
        @ranges.index { |from, to| distance >= from && distance < to } ||
          (@ranges.any? && distance >= @ranges.last[1] - 1e-6 ? @ranges.length - 1 : nil)
      end
    end
  end
end
