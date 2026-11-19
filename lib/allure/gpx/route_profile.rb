# frozen_string_literal: true

module Allure
  module Gpx
    # The route in sections (docs/dev/AI.md §3.3): where the climbing was, and
    # how the moving pace, the heart rate and the grade-adjusted pace of each
    # section compared. Pure and deterministic: it reads the stored points —
    # whose elevations are already the canonical filtered profile
    # (docs/dev/WORKOUT.md) — and never touches the database.
    #
    # The boundaries come from the detected climbs and descents, or from equal
    # parts when the terrain cannot be trusted (`Allure::Insights::CoursePlan`).
    # A pause or a recording gap never bridges two segments, and a pause never
    # counts as a slowdown.
    class RouteProfile
      # A gradient claim needs nearly all the section's distance to carry an
      # elevation: a zero ascent on an uncovered section is missing terrain,
      # never a flat one.
      GRADE_COVERAGE = 0.9

      Section = Data.define(:start_distance, :end_distance, :distance, :moving_time, :ascent, :descent,
                            :elevation_distance, :grade_adjusted_distance, :grade_adjusted_time,
                            :heart_rate_time, :heart_rate_sum) do
        def average_speed
          return if moving_time.to_f <= 0 || distance.to_f <= 0

          distance.to_f / moving_time
        end

        # Seconds per `basis` metres, the pace the payload carries.
        def pace(basis = 1_000)
          speed = average_speed
          return unless speed

          (basis.to_f / speed).round
        end

        # The share of the section's distance whose elevation is known.
        def elevation_coverage
          return 0.0 unless distance.to_f.positive?

          elevation_distance.to_f / distance
        end

        def grade_adjusted_pace
          return if grade_adjusted_distance.to_f <= 0 || grade_adjusted_time.to_f <= 0

          grade_adjusted_time.to_f / (grade_adjusted_distance / 1_000.0)
        end

        # The share of the moving time a grade-adjusted pace could be computed
        # from.
        def grade_adjusted_coverage
          return 0.0 unless moving_time.to_f.positive?

          grade_adjusted_time.to_f / moving_time
        end

        # The average heart rate over the moving time, nil without a sensor.
        def heart_rate
          return unless heart_rate_time.to_f.positive?

          (heart_rate_sum / heart_rate_time).round
        end

        # The net gradient of the section, nil when the elevation is missing.
        def grade
          return unless distance.to_f.positive? && elevation_coverage >= GRADE_COVERAGE

          (ascent.to_f - descent.to_f) / distance.to_f * 100
        end
      end

      Result = Data.define(:distance, :sections) do
        def ascent = sections.sum { it.ascent.to_f }

        def elevation_coverage
          total = distance.to_f
          return 0.0 unless total.positive?

          sections.sum { it.elevation_distance.to_f } / total
        end
      end

      # A mutable accumulator while the points are walked; the result exposes
      # the immutable Section values.
      Accumulator = Struct.new(:start_distance, :end_distance, :distance, :moving_time, :ascent, :descent,
                               :elevation_distance, :grade_adjusted_distance, :grade_adjusted_time,
                               :heart_rate_time, :heart_rate_sum, :pending, keyword_init: true)

      # `stopped_speed_threshold_km_h` is the sport's; `elevation_filter` is the
      # workout's noise class (`barometric`, `gps`, `dem`); `grade_adjusted_pace`
      # is false for the sports where the flat-equivalent pace means nothing.
      def initialize(segments:, workout_started_at:, stopped_speed_threshold_km_h: 0.0,
                     elevation_filter: nil, grade_adjusted_pace: false)
        @segments = segments
        @workout_started_at = workout_started_at
        @stopped_speed_mps = stopped_speed_threshold_km_h.to_f / 3.6
        @elevation_threshold = Elevation.threshold_for(elevation_filter)
        @grade_adjusted_pace = grade_adjusted_pace
      end

      # `boundaries` are absolute recorded distances, in the same scale as the
      # detected laps: the first one usually zero, the last one the workout's
      # own distance. A point beyond the last boundary still belongs to the last
      # section.
      def call(boundaries:)
        points = Segments::PointStream.new(segments: @segments, workout_started_at: @workout_started_at).call
        return if points.length < 3

        edges = Array(boundaries).map(&:to_f)
        return if edges.length < 2

        accumulators = edges.each_cons(2).map { |from, to| blank_section(from, to) }
        ranges = ranges_for(accumulators)
        points.each_cons(2) do |previous, current|
          next unless previous.segment_index == current.segment_index

          from = previous.distance.to_f
          to = current.distance.to_f
          distance = to - from
          next unless distance.positive?

          duration = [ current.time.to_f - previous.time.to_f, 0.0 ].max
          elevation_delta = elevation_delta(previous, current)
          adjustment = adjustment_factor(previous, current, elevation_delta)
          moving = moving?(distance, duration)
          heart = heart_rate_average(previous, current)

          each_share(from, to, ranges) do |index, share|
            accumulate(accumulators[index], share:, distance:, duration:, moving:, elevation_delta:, adjustment:,
                                             heart:)
          end
        end

        sections = accumulators.map { |item| section(item) }
        Result.new(distance: sections.sum { it.distance }, sections:)
      end

      private

      attr_reader :segments, :workout_started_at

      def blank_section(from, to)
        Accumulator.new(start_distance: from, end_distance: to, distance: 0.0, moving_time: 0.0, ascent: 0.0,
                        descent: 0.0, elevation_distance: 0.0, grade_adjusted_distance: 0.0,
                        grade_adjusted_time: 0.0, heart_rate_time: 0.0, heart_rate_sum: 0.0, pending: 0.0)
      end

      # The last price of the route is open: whatever sits beyond the declared
      # distance still belongs to the closing section.
      def ranges_for(accumulators)
        accumulators.each_with_index.map do |item, index|
          to = index == accumulators.length - 1 ? Float::INFINITY : item.end_distance
          [ item.start_distance, to ]
        end
      end

      def accumulate(item, share:, distance:, duration:, moving:, elevation_delta:, adjustment:, heart:)
        part = distance * share
        item.distance += part
        item.moving_time += duration * share if moving
        if elevation_delta
          item.elevation_distance += part
          accumulate_elevation(item, elevation_delta * share)
        end
        if heart && moving
          item.heart_rate_time += duration * share
          item.heart_rate_sum += duration * share * heart
        end
        return unless adjustment && moving

        item.grade_adjusted_distance += part * adjustment
        item.grade_adjusted_time += duration * share
      end

      # The same threshold a split uses: an excursion counts once its net
      # change reaches the noise class's threshold, and the whole excursion is
      # added when it does. A section never inherits its neighbour's pending
      # excursion.
      def accumulate_elevation(item, delta)
        item.pending += delta
        if item.pending >= @elevation_threshold
          item.ascent += item.pending
          item.pending = 0.0
        elsif item.pending <= -@elevation_threshold
          item.descent += -item.pending
          item.pending = 0.0
        end
      end

      # Yields the section index and the share of the interval it covers. An
      # interval may straddle several boundaries when the points are far apart:
      # the loop walks them in order, at most once each.
      def each_share(from, to, ranges)
        length = to - from
        index = 0
        index += 1 while index < ranges.length - 1 && from >= ranges[index][1]

        while index < ranges.length
          range_start, range_end = ranges[index]
          break if range_start >= to

          overlap = [ to, range_end ].min - [ from, range_start ].max
          yield index, overlap / length if overlap.positive?
          index += 1
        end
      end

      def elevation_delta(previous, current)
        return unless Elevation.valid?(previous.elevation) && Elevation.valid?(current.elevation)

        current.elevation - previous.elevation
      end

      # The gradient a grade-adjusted pace would use, when the sport asks for
      # one and both points are positioned.
      def adjustment_factor(previous, current, elevation_delta)
        return unless @grade_adjusted_pace && elevation_delta
        return if previous.latitude.nil? || previous.longitude.nil?
        return if current.latitude.nil? || current.longitude.nil?

        horizontal = Geo.horizontal_distance(previous.latitude, previous.longitude,
                                             current.latitude, current.longitude)
        return unless horizontal.positive?

        GradeAdjustedPace.adjustment_factor(elevation_delta / horizontal)
      end

      # The trapezoid of the interval, nil when either end has no sensor.
      def heart_rate_average(previous, current)
        return unless previous.heart_rate && current.heart_rate

        (previous.heart_rate + current.heart_rate) / 2.0
      end

      def moving?(distance, duration)
        duration.positive? && (distance / duration) > @stopped_speed_mps
      end

      def section(item)
        Section.new(start_distance: item.start_distance, end_distance: item.end_distance, distance: item.distance,
                    moving_time: item.moving_time, ascent: item.ascent, descent: item.descent,
                    elevation_distance: item.elevation_distance,
                    grade_adjusted_distance: item.grade_adjusted_distance,
                    grade_adjusted_time: item.grade_adjusted_time,
                    heart_rate_time: item.heart_rate_time, heart_rate_sum: item.heart_rate_sum)
      end
    end
  end
end
