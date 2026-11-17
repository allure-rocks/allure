# frozen_string_literal: true

module Allure
  module Together
    # Decides whether two recordings are the same outing done together
    # (docs/dev/SHARED-ACTIVITIES.md): compatible sports, no commute, recording windows
    # that overlap enough, and, sampled along the shared window, both athletes
    # at the same place at the same moment most of the time. Pure and linear:
    # each recording is walked once by a forward cursor.
    #
    # A recording is a `Recording` value whose `points` respond to `time`,
    # `latitude` and `longitude` in time order (`Allure::Segments::PointStream`
    # yields them). The result names the match and its two measures; callers
    # never show them to anyone (no score is published).
    class Detector
      VERSION = 1

      # The shared window must last at least the shorter of these.
      MIN_OVERLAP_SECONDS = 20 * 60
      MIN_OVERLAP_RATIO = 0.5
      # A sample is measured every this many seconds of the shared window.
      SAMPLE_STEP_SECONDS = 15
      # A position is interpolated only between points this close in time;
      # beyond it the athlete's position at that moment is unknown. Sparse
      # "smart recording" devices space points up to ~95 s apart (the 99th
      # percentile on the demo ultra-trail), which 60 s rejected.
      TIME_GAP_SECONDS = 120
      # Two positions this close are together.
      DISTANCE_METERS = 60.0
      # The share of the shared window the athletes must spend together.
      MATCH_RATIO = 0.8

      Recording = Data.define(:sport_slug, :virtual, :commute, :moving_time, :points)
      Result = Data.define(:match, :overlap_seconds, :matched_ratio) do
        def match? = match
      end

      NO_MATCH = Result.new(match: false, overlap_seconds: 0, matched_ratio: 0.0)

      def self.call(first, second) = new(first, second).call

      def initialize(first, second)
        @first = first
        @second = second
      end

      def call
        return NO_MATCH unless eligible?

        window_start = [ @first.points.first.time, @second.points.first.time ].max
        window_end = [ @first.points.last.time, @second.points.last.time ].min
        overlap = (window_end - window_start).to_f
        return NO_MATCH if overlap <= 0
        return Result.new(match: false, overlap_seconds: overlap.round, matched_ratio: 0.0) if overlap < required_overlap

        ratio = matched_ratio(window_start, overlap)
        Result.new(match: ratio >= MATCH_RATIO, overlap_seconds: overlap.round, matched_ratio: ratio.round(3))
      end

      private

      def eligible?
        return false if @first.points.empty? || @second.points.empty?
        return false if @first.commute || @second.commute

        SportFamilies.compatible?(@first.sport_slug, @second.sport_slug,
                                  first_virtual: @first.virtual, second_virtual: @second.virtual)
      end

      def required_overlap
        shorter = [ @first.moving_time.to_f, @second.moving_time.to_f ].min
        [ MIN_OVERLAP_SECONDS, shorter * MIN_OVERLAP_RATIO ].min
      end

      # Samples the shared window at a fixed step; a sample counts when both
      # positions are known and close. An unknown position (a pause longer
      # than the gap on one device) counts against the match.
      def matched_ratio(window_start, overlap)
        first_cursor = Cursor.new(@first.points)
        second_cursor = Cursor.new(@second.points)
        samples = (overlap / SAMPLE_STEP_SECONDS).floor + 1
        matched = 0

        samples.times do |index|
          time = window_start + (index * SAMPLE_STEP_SECONDS)
          first_position = first_cursor.position_at(time)
          second_position = second_cursor.position_at(time)
          next unless first_position && second_position

          distance = Allure::Gpx::Geo.horizontal_distance(*first_position, *second_position)
          matched += 1 if distance <= DISTANCE_METERS
        end

        matched.to_f / samples
      end

      # Walks one recording forward and interpolates its position at
      # increasing times, as [latitude, longitude], or nil when unknown.
      class Cursor
        def initialize(points)
          @points = points
          @index = 0
        end

        def position_at(time)
          @index += 1 while @index < @points.length - 1 && @points[@index + 1].time <= time
          before = @points[@index]
          return [ before.latitude, before.longitude ] if before.time == time

          after = @points[@index + 1]
          return nil if after.nil? || before.time > time
          return nil if (after.time - before.time) > TIME_GAP_SECONDS

          fraction = (time - before.time) / (after.time - before.time)
          [
            before.latitude + ((after.latitude - before.latitude) * fraction),
            before.longitude + ((after.longitude - before.longitude) * fraction)
          ]
        end
      end
    end
  end
end
