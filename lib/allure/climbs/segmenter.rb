# frozen_string_literal: true

module Allure
  module Climbs
    # Pure elevation-profile segmentation. One profile, `LAP`, is the single
    # climb definition used by the smart-lap detector and by toponymy sampling,
    # so a climb shown in the Montées tab and a geocoded summit always describe
    # the same slice of the track.
    class Segmenter
      Profile = Data.define(
        :bin_size_metres,
        :smoothing_radius_bins,
        :min_gain_metres,
        :min_climb_distance_metres,
        :max_climb_distance_metres,
        :min_average_grade,
        :min_rising_distance_metres,
        :min_rising_fraction,
        :min_post_peak_distance_metres,
        :max_post_peak_distance_metres,
        :min_prominence_metres,
        :local_peak_radius_metres,
        :min_spacing_metres,
        :max_climbs,
        :max_extension_metres,
        :extend_drop_metres
      ) do
        def initialize(bin_size_metres:, smoothing_radius_bins:, min_gain_metres:,
                       min_climb_distance_metres:, max_climb_distance_metres:,
                       min_average_grade:, min_rising_distance_metres:, min_rising_fraction:,
                       min_post_peak_distance_metres:, max_post_peak_distance_metres:,
                       min_prominence_metres:, local_peak_radius_metres:, min_spacing_metres:,
                       max_climbs:, max_extension_metres:, extend_drop_metres:)
          super
        end
      end

      Climb = Data.define(
        :start_distance,
        :end_distance,
        :length,
        :gain,
        :prominence,
        :start_elevation,
        :peak_elevation,
        :average_grade,
        :max_grade
      ) do
        def initialize(start_distance:, end_distance:, length:, gain:, prominence:,
                       start_elevation:, peak_elevation:, average_grade:, max_grade:)
          super
        end
      end

      LAP = Profile.new(
        bin_size_metres: 50.0,
        smoothing_radius_bins: 1,
        min_gain_metres: 30.0,
        min_climb_distance_metres: 400.0,
        max_climb_distance_metres: 30_000.0,
        min_average_grade: 0.03,
        min_rising_distance_metres: 300.0,
        min_rising_fraction: 0.55,
        min_post_peak_distance_metres: 0.0,
        max_post_peak_distance_metres: 1_000.0,
        min_prominence_metres: 0.0,
        local_peak_radius_metres: 200.0,
        min_spacing_metres: 500.0,
        max_climbs: 12,
        max_extension_metres: 1_000.0,
        extend_drop_metres: 20.0
      )

      # Reaching the true top may dilute the average grade slightly; the
      # extension is kept while it stays within this fraction of the floor.
      EXTENSION_GRADE_RATIO = 0.9

      def initialize(points:, profile: LAP)
        @points = points.filter_map { normalize(it) }.sort_by { it.fetch(:distance) }
        @profile = profile
      end

      def call
        profile = smooth(resample)
        return [] if profile.length < 4

        candidates = profile.each_index.filter_map { candidate_at(profile, it) }
        select_candidates(candidates)
      end

      private

      def normalize(point)
        return unless point.is_a?(Hash)

        distance = numeric(point[:distance] || point["distance"] || point["d"])
        elevation = numeric(point[:elevation] || point["elevation"] || point["ele"])
        return unless distance && elevation

        {
          distance:,
          elevation:,
          latitude: point[:latitude] || point["latitude"] || point["lat"],
          longitude: point[:longitude] || point["longitude"] || point["lon"]
        }
      end

      def resample
        return [] if @points.empty?

        total_distance = @points.last.fetch(:distance)
        target_count = (total_distance / @profile.bin_size_metres).floor
        targets = (0..target_count).map { |index| index * @profile.bin_size_metres }
        targets << total_distance if targets.last < total_distance

        cursor = 0
        targets.filter_map do |target|
          cursor += 1 while cursor + 1 < @points.length && @points[cursor + 1].fetch(:distance) < target
          interpolate(@points[cursor], @points[cursor + 1], target)
        end
      end

      def interpolate(left, right, target)
        return left.merge(distance: target) if right.nil? || left.fetch(:distance) == right.fetch(:distance)
        return unless target.between?(left.fetch(:distance), right.fetch(:distance))

        ratio = (target - left.fetch(:distance)) / (right.fetch(:distance) - left.fetch(:distance))
        { distance: target, elevation: left.fetch(:elevation) + ((right.fetch(:elevation) - left.fetch(:elevation)) * ratio) }
      end

      def smooth(profile)
        profile.each_index.map do |index|
          first = [ index - @profile.smoothing_radius_bins, 0 ].max
          last = [ index + @profile.smoothing_radius_bins, profile.length - 1 ].min
          window = profile[first..last]
          { distance: profile[index].fetch(:distance), elevation: window.sum { it.fetch(:elevation) } / window.length }
        end
      end

      def candidate_at(profile, index)
        peak = profile[index]
        return unless local_peak?(profile, peak)

        candidate = best_valley(profile, index, peak)
        return unless candidate

        valley = candidate.fetch(:valley)
        extended = extend_peak(profile, peak, valley)
        if extended.fetch(:distance) > peak.fetch(:distance)
          climb = build_climb(profile, valley, extended)
          return climb if valid_climb?(climb, grade_ratio: EXTENSION_GRADE_RATIO)
        end

        climb = build_climb(profile, valley, peak)
        return unless valid_climb?(climb)

        climb
      end

      # The latest local minimum before the peak starts the climb, so a flat
      # approach is never swallowed. The walk back stops at the first point
      # higher than the peak: a climb never passes over another summit.
      def best_valley(profile, peak_index, peak)
        return unless sustained_rise?(profile, peak)

        (peak_index - 1).downto(0) do |valley_index|
          valley = profile[valley_index]
          length = peak.fetch(:distance) - valley.fetch(:distance)
          break if length > @profile.max_climb_distance_metres
          break if valley.fetch(:elevation) > peak.fetch(:elevation)
          next if length < @profile.min_climb_distance_metres
          next unless valley_index.zero? || local_minimum?(profile, valley_index)

          gain = peak.fetch(:elevation) - valley.fetch(:elevation)
          next unless gain >= @profile.min_gain_metres && gain / length >= @profile.min_average_grade

          return { valley:, gain: }
        end
        nil
      end

      # A summit can be followed by a short dip before the true top; the climb
      # is extended while the running maximum holds within the drop budget.
      def extend_peak(profile, peak, valley)
        return peak unless @profile.extend_drop_metres.positive?

        limit = [
          peak.fetch(:distance) + @profile.max_extension_metres,
          valley.fetch(:distance) + @profile.max_climb_distance_metres
        ].min
        best = peak
        profile.each do |point|
          distance = point.fetch(:distance)
          next unless distance > peak.fetch(:distance) && distance <= limit

          if point.fetch(:elevation) > best.fetch(:elevation)
            best = point
          elsif best.fetch(:elevation) - point.fetch(:elevation) > @profile.extend_drop_metres
            break
          end
        end
        best
      end

      def build_climb(profile, valley, peak)
        length = peak.fetch(:distance) - valley.fetch(:distance)
        gain = peak.fetch(:elevation) - valley.fetch(:elevation)
        Climb.new(
          start_distance: valley.fetch(:distance),
          end_distance: peak.fetch(:distance),
          length:,
          gain:,
          prominence: prominence(profile, peak),
          start_elevation: valley.fetch(:elevation),
          peak_elevation: peak.fetch(:elevation),
          average_grade: length.positive? ? gain / length : 0.0,
          max_grade: max_grade(profile, valley.fetch(:distance), peak.fetch(:distance))
        )
      end

      def valid_climb?(climb, grade_ratio: 1.0)
        climb.gain >= @profile.min_gain_metres &&
          climb.length.between?(@profile.min_climb_distance_metres, @profile.max_climb_distance_metres) &&
          climb.average_grade >= @profile.min_average_grade * grade_ratio &&
          climb.prominence >= @profile.min_prominence_metres
      end

      def prominence(profile, peak)
        post_peak = profile.select do |point|
          distance = point.fetch(:distance) - peak.fetch(:distance)
          distance > @profile.min_post_peak_distance_metres && distance <= @profile.max_post_peak_distance_metres
        end
        return 0.0 if post_peak.empty?

        peak.fetch(:elevation) - post_peak.min_by { it.fetch(:elevation) }.fetch(:elevation)
      end

      def max_grade(profile, start_distance, end_distance)
        window = profile.select { |point| point.fetch(:distance).between?(start_distance, end_distance) }
        window.each_cons(2).filter_map do |first, second|
          delta = second.fetch(:distance) - first.fetch(:distance)
          next unless delta.positive?

          (second.fetch(:elevation) - first.fetch(:elevation)) / delta
        end.max || 0.0
      end

      def local_peak?(profile, peak)
        profile.all? do |point|
          distance = (point.fetch(:distance) - peak.fetch(:distance)).abs
          distance > @profile.local_peak_radius_metres || point.fetch(:elevation) <= peak.fetch(:elevation)
        end
      end

      def local_minimum?(profile, index)
        @minimum_cache ||= {}
        return @minimum_cache[index] if @minimum_cache.key?(index)

        valley = profile[index]
        @minimum_cache[index] = profile.all? do |point|
          distance = (point.fetch(:distance) - valley.fetch(:distance)).abs
          distance > @profile.local_peak_radius_metres || point.fetch(:elevation) >= valley.fetch(:elevation)
        end
      end

      def sustained_rise?(profile, peak)
        points = profile.select do |point|
          distance = peak.fetch(:distance) - point.fetch(:distance)
          distance.between?(0.0, @profile.min_rising_distance_metres)
        end.sort_by { it.fetch(:distance) }
        deltas = points.each_cons(2).map { it.last.fetch(:elevation) - it.first.fetch(:elevation) }
        return false if deltas.empty?

        deltas.count(&:positive?).fdiv(deltas.length) >= @profile.min_rising_fraction
      end

      # The strongest climbs first, each far enough from the ones already
      # kept and never overlapping them, at most `max_climbs` of them. A bare
      # `break` would hand the caller nil once the cap is reached, so the
      # selection is the value.
      def select_candidates(candidates)
        selected = []
        candidates.sort_by { [ -(it.gain + it.prominence), it.end_distance ] }.each do |candidate|
          next if selected.any? { (it.end_distance - candidate.end_distance).abs < @profile.min_spacing_metres }
          next if selected.any? { it.start_distance < candidate.end_distance && candidate.start_distance < it.end_distance }

          selected << candidate
          break if selected.length >= @profile.max_climbs
        end
        selected.sort_by(&:start_distance)
      end

      def numeric(value)
        value.to_f if value.is_a?(Numeric) && value.to_f.finite?
      end
    end
  end
end
