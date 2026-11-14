# frozen_string_literal: true

module Allure
  module Gpx
    # Turns parsed GPX values into metrics. Pure Ruby, deterministic, and
    # framework-independent: it knows nothing about Active Record, RGeo, or
    # the database. Geometry construction and persistence belong to
    # `Workouts::Importer` (Slice 4).
    #
    # All persisted speed/pace values are SI (metres/second, seconds/km); the
    # sport's `stopped_speed_threshold` is km/h and is converted here only for
    # the moving/stopped threshold comparison, per PLAN_M1.md section 5.1.
    #
    # The analyzer owns the canonical point stream: implausible GPS positions
    # are removed, the elevation profile is filtered once (section 8.6), and
    # every metric, the 3D vertical term, and the serialized points all read
    # that same profile. Consumers downstream re-use the stored points as-is.
    class Analyzer
      VERSION = 15
      POINT_SPEED_WINDOW_SECONDS = 5.0

      Interval = Data.define(:distance, :duration, :speed)

      SegmentMetrics = Data.define(
        :started_at, :duration, :moving_time, :pause_time,
        :distance, :ascent, :descent, :min_elevation, :max_elevation,
        :average_speed, :max_speed, :average_pace, :best_pace,
        :average_heart_rate, :max_heart_rate,
        :average_cadence, :max_cadence,
        :average_power, :max_power,
        :points, :coordinates,
        :heart_rates, :cadences, :powers,
        :grade_adjusted_distance, :grade_adjusted_pace
      )

      WorkoutMetrics = Data.define(
        :started_at, :duration, :moving_time, :pause_time,
        :distance, :ascent, :descent, :min_elevation, :max_elevation,
        :average_speed, :max_speed, :average_pace, :best_pace,
        :average_heart_rate, :max_heart_rate,
        :average_cadence, :max_cadence,
        :average_power, :max_power,
        :calories, :points_count, :bounds, :start_point, :segments,
        :grade_adjusted_pace, :elevation_filter, :anomalies
      )

      # `speed_ceiling_km_h` is the sport's plausible maximum, used only to
      # flag anomalies (section 8.10); it never changes a metric.
      def initialize(stopped_speed_threshold_km_h:, records_elevation: true, grade_adjusted_pace: true, elevation_filter: nil,
                     speed_ceiling_km_h: nil)
        @stopped_speed_threshold_km_h = stopped_speed_threshold_km_h.to_f
        @records_elevation = records_elevation
        @grade_adjusted_pace = grade_adjusted_pace
        @forced_elevation_filter = elevation_filter&.to_sym
        @speed_ceiling_km_h = speed_ceiling_km_h
      end

      def analyze(track)
        raise ArgumentError, "at least one segment is required" if track.segments.empty?

        # An unpositioned recording has no geometry to clean or elevate: every
        # timed record is a data point, and distance and speed come from the
        # device itself (PLAN_NO_GPS.md §4).
        cleaned_segments = track.segments.map do |segment|
          segment.positioned? ? Outliers.filter(segment.points) : segment.points
        end
        elevation_filter = @records_elevation && track.positioned? ? workout_elevation_filter(cleaned_segments) : nil
        segment_metrics = cleaned_segments.map { |points| analyze_segment(points, elevation_filter:) }
        attributes = workout_attributes(segment_metrics, source_max_speed: track.source_max_speed)

        WorkoutMetrics.new(
          **attributes,
          calories: track.calories,
          segments: segment_metrics,
          elevation_filter:,
          anomalies: Anomalies.new(
            raw_segments: track.segments.map(&:points),
            cleaned_segments:,
            segment_metrics:,
            started_at: attributes[:started_at],
            speed_ceiling_km_h: @speed_ceiling_km_h,
            stopped_speed_threshold_km_h: @stopped_speed_threshold_km_h,
            records_elevation: @records_elevation,
            recorded_max_speed: attributes[:max_speed],
            elevation_filter:
          ).call
        )
      end

      private

      # One noise class for the whole workout keeps the segment metrics and
      # every downstream consumer on the same ascent threshold. A DEM profile
      # is forced to the DEM class by its caller: linear interpolation between
      # terrain samples is smoother than a barometer yet carries several metres
      # of model error. An absent or unusable profile stays nil.
      def workout_elevation_filter(cleaned_segments)
        classes = cleaned_segments.filter_map do |points|
          elevations = points.map(&:elevation)
          next unless elevations.any? { |elevation| Elevation.valid?(elevation) }

          Elevation.noise_class(elevations, distances: cumulative_horizontal_distances(points))
        end
        return nil if classes.empty?
        return @forced_elevation_filter if @forced_elevation_filter

        classes.include?(:gps) ? :gps : :barometric
      end

      def analyze_segment(points, elevation_filter:)
        return analyze_positionless_segment(points) unless points.first.positioned?

        distances = cumulative_horizontal_distances(points)
        raw_elevations = @records_elevation ? points.map(&:elevation) : []
        analysis_elevations = @records_elevation ? canonical_elevations(raw_elevations, distances, elevation_filter) : []
        analysis_points = @records_elevation ? substitute_elevations(points, analysis_elevations) : points
        intervals = build_intervals(analysis_points)

        distance = intervals.sum(&:distance)
        duration = round(points.last.time - points.first.time)
        moving_time = round(intervals.sum { |interval| moving?(interval) ? interval.duration : 0.0 })

        ascent, descent = Elevation.ascent_and_descent(
          analysis_elevations,
          threshold: Elevation.threshold_for(elevation_filter)
        )
        max_speed = MaxSpeed.calculate(intervals)
        average_speed = moving_time.positive? ? distance / moving_time : 0.0

        heart_rates = points.filter_map { |point| positive_heart_rate(point.heart_rate) }
        cadences = points.filter_map(&:cadence)
        powers = points.filter_map(&:power)

        gap_result = if @grade_adjusted_pace && @records_elevation
          Allure::Gpx::GradeAdjustedPace.from_points(analysis_points, stopped_speed_threshold_km_h: @stopped_speed_threshold_km_h)
        end
        grade_adjusted_distance = gap_result&.[](:grade_adjusted_distance)
        grade_adjusted_pace = if grade_adjusted_distance && moving_time.positive?
          (moving_time / (grade_adjusted_distance / 1000.0)).round
        end

        SegmentMetrics.new(
          started_at: points.first.time,
          duration:,
          moving_time:,
          pause_time: duration - moving_time,
          distance:,
          ascent:,
          descent:,
          min_elevation: Elevation.minimum(analysis_elevations),
          max_elevation: Elevation.maximum(analysis_elevations),
          average_speed:,
          max_speed:,
          average_pace: pace_for(average_speed),
          best_pace: pace_for(max_speed),
          average_heart_rate: mean_of(heart_rates),
          max_heart_rate: heart_rates.max,
          average_cadence: mean_of(cadences),
          max_cadence: cadences.max,
          average_power: mean_of(powers),
          max_power: powers.max,
          points: serialize_points(analysis_points, intervals),
          coordinates: points.map { |point| [ point.longitude, point.latitude ] },
          heart_rates:,
          cadences:,
          powers:,
          grade_adjusted_distance:,
          grade_adjusted_pace:
        )
      end

      # An indoor activity (PLAN_NO_GPS.md §4): no coordinates, so no
      # outlier removal, no elevation, no GAP, no geodesic distance. Distance
      # and speed come from the device's own records — its cumulative
      # `distance`, its speed, one filling the other's gaps; a recording with
      # neither reads as a duration-only session (distance 0) whose timer time
      # is moving time, because the device recorded no stop.
      def analyze_positionless_segment(points)
        intervals = build_positionless_intervals(points)
        distance = intervals.sum(&:distance)
        duration = round(points.last.time - points.first.time)
        moving = intervals.filter_map { |interval| positionless_moving?(interval, points) ? interval.duration : nil }.sum
        moving_time = round(moving)
        max_speed = MaxSpeed.calculate(intervals)
        average_speed = moving_time.positive? ? distance / moving_time : 0.0

        heart_rates = points.filter_map { |point| positive_heart_rate(point.heart_rate) }
        cadences = points.filter_map(&:cadence)
        powers = points.filter_map(&:power)

        SegmentMetrics.new(
          started_at: points.first.time,
          duration:,
          moving_time:,
          pause_time: duration - moving_time,
          distance:,
          ascent: 0.0,
          descent: 0.0,
          min_elevation: nil,
          max_elevation: nil,
          average_speed:,
          max_speed:,
          average_pace: pace_for(average_speed),
          best_pace: pace_for(max_speed),
          average_heart_rate: mean_of(heart_rates),
          max_heart_rate: heart_rates.max,
          average_cadence: mean_of(cadences),
          max_cadence: cadences.max,
          average_power: mean_of(powers),
          max_power: powers.max,
          points: serialize_positionless_points(points, intervals),
          coordinates: [],
          heart_rates:,
          cadences:,
          powers:,
          grade_adjusted_distance: nil,
          grade_adjusted_pace: nil
        )
      end

      # One interval per pair of consecutive records, in the same shape and
      # order as a positioned recording's, so the max-speed window, the point
      # speeds and the serialized cumulative distances all keep working.
      #
      # The device's cumulative distance is authoritative: it is what the
      # trainer, pod or erg actually measured, and it is preferred to this
      # pair of boundary readings' speed. A cumulative distance that does not
      # advance is a standstill, never distance integrated from a stale speed
      # (PLAN_NO_GPS.md §4.1). When the cumulative distance is missing from
      # the file, the interval is the device speed over its own duration;
      # when neither is recorded, it is a duration-only interval.
      #
      # The device's offset is dropped by using the first record's cumulative
      # distance as the origin: trainers and ergs commonly count from their
      # lifetime total.
      def build_positionless_intervals(points)
        previous_distance = first_distance(points)
        distances_recorded = !previous_distance.nil? || points.any? { |point| !device_value(point.distance).nil? }

        points.each_cons(2).map do |previous_point, current_point|
          delta = current_point.time - previous_point.time
          duration = [ delta, 0.0 ].max
          speed = device_value(current_point.speed)
          # Without a cumulative distance anywhere, the device speed measures
          # the movement; the boundary reading stands for its interval.
          speed = nil if speed && distances_recorded
          recorded = device_value(current_point.distance)
          # A backward step is a sensor reset, not negative ground, and is
          # treated as a standstill.
          recorded = previous_distance if !recorded.nil? && !previous_distance.nil? && recorded < previous_distance
          distance = if recorded.nil?
            speed.nil? || !delta.positive? ? 0.0 : speed * delta
          else
            [ recorded - (previous_distance.nil? ? recorded : previous_distance), 0.0 ].max
          end
          speed = distance / delta if speed.nil? && delta.positive?
          speed = 0.0 if speed.nil?
          previous_distance = recorded

          Interval.new(distance:, duration:, speed:)
        end
      end

      # The first recorded cumulative distance, or nil when the file records
      # none: trainers and ergs commonly count from their lifetime total, so
      # the first record is the origin.
      def first_distance(points)
        points.each { |point| return device_value(point.distance) unless device_value(point.distance).nil? }
        nil
      end

      # The canonical profile is rounded to the stored point precision before
      # any metric reads it, so a downstream consumer recomputing ascent from
      # `ele` reproduces the analyzer value exactly.
      def canonical_elevations(elevations, distances, elevation_filter)
        Elevation
          .filter(elevations, distances:, noise_class: elevation_filter)
          .map { |elevation| elevation&.round(1) }
      end

      def substitute_elevations(points, elevations)
        points.each_with_index.map do |point, index|
          next point if point.elevation == elevations[index]

          point.with(elevation: elevations[index])
        end
      end

      def cumulative_horizontal_distances(points)
        cumulative = [ 0.0 ]
        points.each_cons(2) do |previous_point, current_point|
          cumulative << cumulative.last + Geo.horizontal_distance(
            previous_point.latitude, previous_point.longitude,
            current_point.latitude, current_point.longitude
          )
        end
        cumulative
      end

      def build_intervals(points)
        points.each_cons(2).map do |previous_point, current_point|
          delta = current_point.time - previous_point.time
          # The distance is the recorded path length, independent of timestamp
          # resolution: second-precision exports repeat timestamps across real
          # movement, and that movement still belongs to the workout. Only
          # moving time and speed require positive time (PLAN_M1.md §8.1/§8.3).
          distance = delta.negative? ? 0.0 : point_distance(previous_point, current_point)
          duration = [ delta, 0.0 ].max
          speed = duration.positive? ? distance / duration : 0.0
          Interval.new(distance:, duration:, speed:)
        end
      end

      # Sports that do not record elevation always use 2D distance, even if
      # the file happens to supply elevation values (PLAN_M1.md section 8.6).
      def point_distance(previous_point, current_point)
        return Geo.distance(previous_point, current_point) if @records_elevation

        Geo.horizontal_distance(previous_point.latitude, previous_point.longitude, current_point.latitude, current_point.longitude)
      end

      def moving?(interval)
        return false unless interval.duration.positive?

        Allure::Units.metres_per_second_to_kilometres_per_hour(interval.speed) > @stopped_speed_threshold_km_h
      end

      # A positionless interval follows the same stopped-speed threshold as a
      # positioned one as soon as the file recorded any movement data — a
      # cumulative distance or a device speed (PLAN_NO_GPS.md §4.2). A file
      # with neither is a duration-only session: its timer ran, so all of its
      # time is moving time and the only pause is a timer stop.
      def positionless_moving?(interval, points)
        return false unless interval.duration.positive?
        return true unless positionless_movement_data?(points)

        Allure::Units.metres_per_second_to_kilometres_per_hour(interval.speed) > @stopped_speed_threshold_km_h
      end

      def positionless_movement_data?(points)
        points.any? { |point| !device_value(point.distance).nil? || !device_value(point.speed).nil? }
      end

      # A finite, non-negative numeric reading from the file, or nil. The
      # device's own distance and speed boundaries are checked here rather
      # than trusted from the parser.
      def device_value(value)
        return nil unless value.is_a?(Numeric)

        number = value.to_f
        number if number.finite? && number >= 0
      end

      def serialize_points(points, intervals)
        cumulative_distance = 0.0
        segment_start = points.first.time
        speeds = point_speeds(points, intervals)

        points.each_index.map do |index|
          point = points[index]
          incoming = intervals[index - 1] if index.positive?
          cumulative_distance += incoming.distance if incoming

          PointSerializer.serialize(
            time_offset_seconds: round(point.time - segment_start),
            cumulative_distance_metres: cumulative_distance,
            latitude: point.latitude,
            longitude: point.longitude,
            elevation: @records_elevation && Elevation.valid?(point.elevation) ? point.elevation : nil,
            speed_metres_per_second: speeds[index],
            heart_rate: positive_heart_rate(point.heart_rate),
            cadence: point.cadence,
            power: point.power,
            temperature: point.temperature
          )
        end
      end

      # A positionless point is serialized through the same seam as a
      # positioned one, minus the coordinates and the elevation. Its plotted
      # speed is the device's own reading; where the device recorded none, the
      # interval's computed speed stands in. A speed that rounds to nothing is
      # left out so `v` never claims motion that did not happen
      # (PLAN_NO_GPS.md §5).
      def serialize_positionless_points(points, intervals)
        cumulative_distance = 0.0
        segment_start = points.first.time

        points.each_index.map do |index|
          point = points[index]
          incoming = intervals[index - 1] if index.positive?
          cumulative_distance += incoming.distance if incoming

          speed = device_value(point.speed)
          speed = intervals[index].speed if speed.nil? && intervals[index]
          speed = 0.0 if speed.nil? && index.positive?
          speed = nil if speed && speed.round(2).zero?

          PointSerializer.serialize(
            time_offset_seconds: round(point.time - segment_start),
            cumulative_distance_metres: cumulative_distance,
            speed_metres_per_second: speed,
            heart_rate: positive_heart_rate(point.heart_rate),
            cadence: point.cadence,
            power: point.power,
            temperature: point.temperature
          )
        end
      end

      # Point speed is the mean of every interval speed overlapping a short
      # centred window. A one-second interval pair is far too sensitive to GPS
      # jitter to be displayed as-is. Timestamps are monotonic, so the
      # overlapping intervals form a sliding range.
      def point_speeds(points, intervals)
        half_window = POINT_SPEED_WINDOW_SECONDS / 2.0
        left = 0
        right = 0
        sum = 0.0
        count = 0

        points.each_index.map do |index|
          time = points[index].time
          window_start = time - half_window
          window_end = time + half_window

          while right < intervals.length && points[right].time <= window_end
            interval = intervals[right]
            if interval.duration.positive?
              sum += interval.speed
              count += 1
            end
            right += 1
          end

          while left < right && points[left + 1].time < window_start
            interval = intervals[left]
            if interval.duration.positive?
              sum -= interval.speed
              count -= 1
            end
            left += 1
          end

          count.positive? ? sum / count : nil
        end
      end

      def pace_for(speed)
        return nil if speed.nil? || !speed.positive?

        round(1000.0 / speed)
      end

      def mean_of(values)
        return nil if values.empty?

        round(values.sum.to_f / values.length)
      end

      # Defense-in-depth for points built without a parser (tests, old
      # rows): strap dropouts arrive as 0 bpm, never a valid heart rate.
      def positive_heart_rate(value)
        value if value.is_a?(Numeric) && value.positive?
      end

      def round(number) = number.round.to_i

      def workout_attributes(segment_metrics, source_max_speed:)
        distance = segment_metrics.sum(&:distance)
        moving_time = segment_metrics.sum(&:moving_time)
        duration = segment_metrics.sum(&:duration) + inter_segment_gaps(segment_metrics)
        average_speed = moving_time.positive? ? distance / moving_time : 0.0
        max_speed = if source_max_speed&.positive? && source_max_speed.finite?
          source_max_speed
        else
          segment_metrics.filter_map(&:max_speed).max
        end
        # A positionless recording (or an all-unpositioned mixed one) has no
        # bounds and no start point: the workout is stored without either
        # (PLAN_NO_GPS.md §5).
        latitudes = segment_metrics.flat_map { |segment| segment.coordinates.map { |_lon, lat| lat } }
        longitudes = segment_metrics.flat_map { |segment| segment.coordinates.map { |lon, _lat| lon } }
        positioned = latitudes.any? && longitudes.any?
        starting_segment = segment_metrics.min_by(&:started_at)
        min_elevations = segment_metrics.filter_map(&:min_elevation)
        max_elevations = segment_metrics.filter_map(&:max_elevation)
        grade_adjusted_distance = segment_metrics.sum { |segment| segment.grade_adjusted_distance || 0.0 }
        grade_adjusted_pace = if segment_metrics.all? { |segment| segment.grade_adjusted_distance } && segment_metrics.any? { _1.moving_time.positive? }
          (grade_adjusted_distance.positive? && moving_time.positive?) ? (moving_time / (grade_adjusted_distance / 1000.0)).round : nil
        else
          nil
        end

        {
          started_at: starting_segment.started_at,
          duration:,
          moving_time:,
          pause_time: duration - moving_time,
          distance:,
          ascent: segment_metrics.sum(&:ascent),
          descent: segment_metrics.sum(&:descent),
          min_elevation: min_elevations.min,
          max_elevation: max_elevations.max,
          average_speed:,
          max_speed:,
          average_pace: pace_for(average_speed),
          best_pace: pace_for(max_speed),
          average_heart_rate: mean_of(segment_metrics.flat_map(&:heart_rates)),
          max_heart_rate: segment_metrics.filter_map(&:max_heart_rate).max,
          average_cadence: mean_of(segment_metrics.flat_map(&:cadences)),
          max_cadence: segment_metrics.filter_map(&:max_cadence).max,
          average_power: mean_of(segment_metrics.flat_map(&:powers)),
          max_power: segment_metrics.filter_map(&:max_power).max,
          points_count: segment_metrics.sum { |segment| segment.points.length },
          bounds: positioned ? [ latitudes.min, longitudes.min, latitudes.max, longitudes.max ] : nil,
          start_point: positioned ? starting_segment.coordinates.first : nil,
          grade_adjusted_pace:
        }
      end

      # Gaps are measured between consecutive segments in document order
      # (position order), matching how segments are persisted. A negative gap
      # means a later document-order segment started before an earlier one
      # finished, which is invalid input; M1 does not silently reorder
      # segments to compensate.
      def inter_segment_gaps(segment_metrics)
        segment_metrics.each_cons(2).sum do |previous_segment, current_segment|
          gap = current_segment.started_at - (previous_segment.started_at + previous_segment.duration)
          raise NonMonotonicTimestampError, "segments overlap in document order" if gap.negative?

          gap.round.to_i
        end
      end
    end
  end
end
