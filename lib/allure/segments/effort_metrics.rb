# frozen_string_literal: true

module Allure
  module Segments
    Effort = Data.define(
      :occurrence_index,
      :started_at,
      :elapsed_time,
      :moving_time,
      :distance,
      :ascent,
      :descent,
      :average_speed,
      :average_pace,
      :average_heart_rate,
      :max_heart_rate,
      :average_cadence,
      :average_power,
      :max_power,
      :start_offset_meters,
      :start_point_index,
      :end_point_index,
      :deviation_meters,
      :grade_adjusted_pace
    ) do
      def initialize(
        occurrence_index:,
        started_at:,
        elapsed_time:,
        moving_time:,
        distance:,
        ascent:,
        descent:,
        average_speed:,
        average_pace:,
        average_heart_rate:,
        max_heart_rate:,
        average_cadence:,
        average_power:,
        max_power:,
        start_offset_meters:,
        start_point_index:,
        end_point_index:,
        deviation_meters:,
        grade_adjusted_pace:
      )
        super
      end
    end

    class EffortMetrics
      Summary = Data.define(:occurrence_index, :started_at, :elapsed_time, :distance, :start_point_index, :end_point_index)
      def initialize(
        points:,
        candidate_start_index:,
        start_projection:,
        end_projection:,
        deviation_meters:,
        occurrence_index:,
        stopped_speed_threshold_km_h: 0.0,
        grade_adjusted_pace: false,
        elevation_filter: nil
      )
        @points = points
        @candidate_start_index = candidate_start_index
        @start_projection = start_projection
        @end_projection = end_projection
        @deviation_meters = deviation_meters
        @occurrence_index = occurrence_index
        @stopped_speed_threshold_mps = stopped_speed_threshold_km_h.to_f / 3.6
        @grade_adjusted_pace = grade_adjusted_pace
        @elevation_filter = elevation_filter
      end

      def call
        samples = samples_for_effort
        elapsed_seconds = samples.last.time - samples.first.time
        elapsed_time = elapsed_seconds.round
        return if elapsed_time <= 0

        distance = samples.last.distance - samples.first.distance
        return if distance.negative?

        intervals = samples.each_cons(2).map { |first, second| interval(first, second) }
        moving_time = intervals.sum(0.0) { |value| value[:moving] ? value[:duration] : 0.0 }.round.clamp(0, elapsed_time)
        average_speed = moving_time.positive? ? distance / moving_time : 0.0
        elevations = elevation_metrics(samples)
        heart_rates = samples.filter_map { |sample| sample.heart_rate if sample.heart_rate.is_a?(Numeric) && sample.heart_rate.positive? }
        cadences = samples.filter_map(&:cadence)
        powers = samples.filter_map(&:power)

        gap_result = @grade_adjusted_pace ? Allure::Gpx::GradeAdjustedPace.from_points(samples, stopped_speed_threshold_km_h: @stopped_speed_threshold_km_h) : nil
        grade_adjusted_pace_value = gap_result ? (gap_result[:moving_time] / (gap_result[:grade_adjusted_distance] / 1000.0)).round : nil

        Effort.new(
          occurrence_index: @occurrence_index,
          started_at: samples.first.time,
          elapsed_time: elapsed_time,
          moving_time: moving_time,
          distance: distance,
          ascent: elevations[:ascent],
          descent: elevations[:descent],
          average_speed: average_speed,
          average_pace: average_speed&.positive? ? (1_000.0 / average_speed).round : nil,
          average_heart_rate: rounded_mean(heart_rates),
          max_heart_rate: rounded_max(heart_rates),
          average_cadence: rounded_mean(cadences),
          average_power: rounded_mean(powers),
          max_power: rounded_max(powers),
          start_offset_meters: samples.first.distance,
          start_point_index: start_point_index,
          end_point_index: end_point_index,
          deviation_meters: @deviation_meters,
          grade_adjusted_pace: grade_adjusted_pace_value
        )
      end

      # Candidate selection needs coverage and valid duration, not sensor,
      # elevation or GAP calculations for every speculative circuit. These
      # are the exact same interpolated boundaries as the full effort below.
      def summary
        first = interpolated_sample(@candidate_start_index + @start_projection.segment_index,
          @start_projection.fraction, @start_projection)
        last = interpolated_sample(@candidate_start_index + @end_projection.segment_index,
          @end_projection.fraction, @end_projection)
        elapsed_time = (last.time - first.time).round
        distance = last.distance - first.distance
        return if elapsed_time <= 0 || distance.negative?

        Summary.new(occurrence_index: @occurrence_index, started_at: first.time,
          elapsed_time:, distance:, start_point_index:, end_point_index:)
      end

      private

      Sample = Data.define(:time, :distance, :longitude, :latitude, :elevation, :heart_rate, :cadence, :power) do
        def initialize(time:, distance:, longitude:, latitude:, elevation:, heart_rate:, cadence:, power:)
          super
        end

        def coordinate = [ longitude, latitude ].freeze
      end

      def samples_for_effort
        start_index = @candidate_start_index + @start_projection.segment_index
        end_index = @candidate_start_index + @end_projection.segment_index + 1
        samples = [ interpolated_sample(start_index, @start_projection.fraction, @start_projection) ]
        first_inner_index = start_index + (@start_projection.fraction == 1.0 ? 2 : 1)
        last_inner_index = end_index - (@end_projection.fraction.zero? ? 2 : 1)
        if first_inner_index <= last_inner_index
          samples.concat(@points[first_inner_index..last_inner_index].map { |point| sample_from(point) })
        end
        samples << interpolated_sample(end_index - 1, @end_projection.fraction, @end_projection)
        samples
      end

      def interpolated_sample(index, fraction, projection)
        first = @points[index]
        second = @points[index + 1]
        Sample.new(
          time: projection.time,
          distance: first.distance + ((second.distance - first.distance) * fraction),
          longitude: projection.coordinate.first,
          latitude: projection.coordinate.last,
          elevation: interpolate_optional(first.elevation, second.elevation, fraction),
          heart_rate: interpolate_heart_rate(first.heart_rate, second.heart_rate, fraction),
          cadence: interpolate_optional(first.cadence, second.cadence, fraction),
          power: interpolate_optional(first.power, second.power, fraction)
        )
      end

      def sample_from(point)
        Sample.new(
          time: point.time,
          distance: point.distance,
          longitude: point.longitude,
          latitude: point.latitude,
          elevation: point.elevation,
          heart_rate: positive_heart_rate(point.heart_rate),
          cadence: point.cadence,
          power: point.power
        )
      end

      def interpolate_optional(first, second, fraction)
        return unless first && second

        first + ((second - first) * fraction)
      end

      # Strap dropouts stored as 0 in old rows must not pull an
      # interpolated endpoint toward zero.
      def interpolate_heart_rate(first, second, fraction)
        first = positive_heart_rate(first)
        second = positive_heart_rate(second)
        return unless first && second

        interpolate_optional(first, second, fraction)
      end

      def positive_heart_rate(value)
        value if value.is_a?(Numeric) && value.positive?
      end

      def interval(first, second)
        duration = second.time - first.time
        distance = second.distance - first.distance
        speed = duration.positive? ? distance / duration : 0.0
        { duration: duration, moving: duration.positive? && speed > @stopped_speed_threshold_mps }
      end

      # Stored elevations are already the canonical filtered profile; only the
      # threshold accumulator runs here.
      def elevation_metrics(samples)
        ascent, descent = Allure::Gpx::Elevation.ascent_and_descent(
          samples.map(&:elevation),
          threshold: Allure::Gpx::Elevation.threshold_for(@elevation_filter)
        )
        { ascent:, descent: }
      end

      def rounded_mean(values)
        values.empty? ? nil : (values.sum.to_f / values.length).round
      end

      # Interpolated endpoint samples are floats even for integer sensor
      # sources (e.g. `0` becomes `0.0`), while `SegmentEffort` columns are
      # integers. Rounding here keeps every persisted effort valid; without
      # it a single float max aborts the whole workout transaction.
      def rounded_max(values)
        values.max&.round
      end

      def start_point_index
        @candidate_start_index + @start_projection.segment_index
      end

      def end_point_index
        @candidate_start_index + @end_projection.segment_index + (@end_projection.fraction.positive? ? 1 : 0)
      end
    end
  end
end
