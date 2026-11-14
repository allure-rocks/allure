# frozen_string_literal: true

module Allure
  module Segments
    class Matcher
      VERSION = 4
      ANCHOR_SPACING_METERS = 10.0
      SIGNATURE_L1_THRESHOLD = 16.0
      MIN_LENGTH_RATIO = 0.8
      MAX_LENGTH_RATIO = 1.3
      ROUTE_MIN_LENGTH_RATIO = 0.9
      ROUTE_MAX_LENGTH_RATIO = 1.1

      def initialize(segment:, points:, stopped_speed_threshold_km_h: 0.0, grade_adjusted_pace: false, elevation_filter: nil)
        @segment = segment
        @points = points
        @stopped_speed_threshold_km_h = stopped_speed_threshold_km_h
        @grade_adjusted_pace = grade_adjusted_pace
        @elevation_filter = elevation_filter
      end

      def call(summary_only: false)
        return [] if @points.length < 2

        return route_efforts(summary_only:) if route?

        anchors = Allure::Geometry::Resampler.resample(
          segment_coordinates,
          spacing: ANCHOR_SPACING_METERS
        )
        entries = endpoint_candidates(anchors.first)
        exits = endpoint_candidates(anchors.last)
        matches = endpoint_pairs(entries, exits).filter_map { |entry, exit| match(entry, exit, anchors) }

        selected = []
        best_traversal_per_entry(matches).each do |match|
          next if selected.any? { |selected_match| match[:start_index] < selected_match[:end_index] }

          selected << match
        end

        selected.each_with_index.filter_map do |match, occurrence_index|
          Allure::Segments::EffortMetrics.new(
            points: @points,
            candidate_start_index: match[:start_index],
            start_projection: match[:start_projection],
            end_projection: match[:end_projection],
            deviation_meters: match[:deviation_meters],
            occurrence_index: occurrence_index,
            stopped_speed_threshold_km_h: @stopped_speed_threshold_km_h,
            grade_adjusted_pace: @grade_adjusted_pace,
            elevation_filter: @elevation_filter
          ).public_send(summary_only ? :summary : :call)
        end
      end

      private

      # Hundreds of loop repetitions must not allocate the Cartesian product
      # of every entry and exit. Distance is monotonic across the point stream;
      # this prefilter excludes only pairs match() would reject anyway.
      def endpoint_pairs(entries, exits)
        return entries.product(exits) unless @segment.kind == "loop"

        Enumerator.new do |pairs|
          entries.each do |entry|
            minimum = @points[entry].distance + @segment.distance * MIN_LENGTH_RATIO - 1e-6
            maximum = @points[entry].distance + @segment.distance * MAX_LENGTH_RATIO + 1e-6
            first = exits.bsearch_index { |exit| @points[exit].distance >= minimum }
            next unless first

            index = first
            while index < exits.length && @points[exits[index]].distance <= maximum
              pairs << [ entry, exits[index] ]
              index += 1
            end
          end
        end
      end

      def route?
        @segment.kind == "route"
      end

      # A route is a segment matched end to end: the whole workout stream is the
      # single candidate. The traversal is anchored to the first and last points,
      # so it may span recording-segment boundaries that would reject a partial
      # segment. The length window is tighter than a segment's (±10 %).
      def route_efforts(summary_only: false)
        match = match_route
        return [] unless match

        effort = Allure::Segments::EffortMetrics.new(
          points: @points,
          candidate_start_index: match[:start_index],
          start_projection: match[:start_projection],
          end_projection: match[:end_projection],
          deviation_meters: match[:deviation_meters],
          occurrence_index: 0,
          stopped_speed_threshold_km_h: @stopped_speed_threshold_km_h,
          grade_adjusted_pace: @grade_adjusted_pace,
          elevation_filter: @elevation_filter
        ).public_send(summary_only ? :summary : :call)
        effort ? [ effort ] : []
      end

      def match_route
        anchors = Allure::Geometry::Resampler.resample(
          segment_coordinates,
          spacing: ANCHOR_SPACING_METERS
        )
        start_index = 0
        end_index = @points.length - 1
        return nil if end_index <= start_index

        total_distance = @points.last.distance - @points.first.distance
        return nil unless total_distance.between?(@segment.distance * ROUTE_MIN_LENGTH_RATIO, @segment.distance * ROUTE_MAX_LENGTH_RATIO)

        return nil if horizontal_distance(@points.first.coordinate, anchors.first) > @segment.match_tolerance_meters
        return nil if horizontal_distance(@points.last.coordinate, anchors.last) > @segment.match_tolerance_meters

        candidate_coordinates = @points.map(&:coordinate)
        return nil if signature_distance(candidate_coordinates) > SIGNATURE_L1_THRESHOLD

        candidate_anchors = Allure::Geometry::Resampler.resample(
          candidate_coordinates,
          spacing: ANCHOR_SPACING_METERS
        )
        deviation_meters = Allure::Geometry::Frechet.distance(anchors, candidate_anchors)
        return nil if deviation_meters > @segment.match_tolerance_meters

        times = @points.map(&:time)
        {
          start_index:,
          end_index:,
          start_projection: project_endpoint(target: anchors.first, polyline: candidate_coordinates, times:, from_start: true),
          end_projection: project_endpoint(target: anchors.last, polyline: candidate_coordinates, times:, from_start: false),
          deviation_meters:,
          endpoint_residual_meters: nil
        }
      end

      # An entry may bracket several plausible exits, typically because the route
      # passes near its own end before finishing. Preferring the exit that lands
      # closest to the canonical end avoids truncating the effort.
      def best_traversal_per_entry(matches)
        matches
          .group_by { |match| match[:start_index] }
          .values
          .map { |group| group.min_by { |match| [ match[:endpoint_residual_meters], match[:deviation_meters], match[:end_index] ] } }
          .sort_by { |match| match[:start_index] }
      end

      # Bounded by the shape tolerance on purpose. Discrete Fréchet couples first
      # to first and last to last, so it is always at least the endpoint gap:
      # any pair whose endpoints exceed this tolerance is provably rejected by
      # the verdict below. Searching wider can never admit a match, only cost.
      def endpoint_candidates(target)
        distances = @points.map { |point| horizontal_distance(point.coordinate, target) }
        distances.each_index.select do |index|
          distance = distances[index]
          next false if distance > @segment.match_tolerance_meters

          before = distances[index - 1] if index.positive?
          after = distances[index + 1] if index < distances.length - 1
          (before.nil? || distance <= before) && (after.nil? || distance <= after) &&
            (before.nil? || distance < before || after.nil? || distance < after)
        end
      end

      def match(start_index, end_index, anchors)
        return if end_index <= start_index
        return if @points[start_index].segment_index != @points[end_index].segment_index

        traversed_distance = @points[end_index].distance - @points[start_index].distance
        return unless traversed_distance.between?(@segment.distance * MIN_LENGTH_RATIO, @segment.distance * MAX_LENGTH_RATIO)

        candidate_coordinates = @points[start_index..end_index].map(&:coordinate)
        return if signature_distance(candidate_coordinates) > SIGNATURE_L1_THRESHOLD

        candidate_anchors = Allure::Geometry::Resampler.resample(
          candidate_coordinates,
          spacing: ANCHOR_SPACING_METERS
        )
        options = @segment.kind == "loop" ? { ceiling: @segment.match_tolerance_meters } : {}
        deviation_meters = Allure::Geometry::Frechet.distance(anchors, candidate_anchors, **options)
        return if deviation_meters > @segment.match_tolerance_meters

        times = @points[start_index..end_index].map(&:time)
        start_projection = project_endpoint(
          target: anchors.first,
          polyline: candidate_coordinates,
          times:,
          from_start: true
        )
        end_projection = project_endpoint(
          target: anchors.last,
          polyline: candidate_coordinates,
          times:,
          from_start: false
        )
        return if end_projection.distance_along_meters <= start_projection.distance_along_meters

        {
          start_index: start_index,
          end_index: end_index,
          start_projection: start_projection,
          end_projection: end_projection,
          deviation_meters: deviation_meters,
          endpoint_residual_meters: start_projection.distance_meters + end_projection.distance_meters
        }
      end

      def signature_distance(candidate_coordinates)
        candidate_signature = Allure::Geometry::ShapeSignature.compute(candidate_coordinates)
        @segment.signature.zip(candidate_signature).sum { |expected, actual| (expected - actual).abs }
      end

      def segment_coordinates
        @segment.geom.points.map { |point| [ point.x, point.y ] }
      end

      # Deliberately anchored to the bracketing endpoint rather than to an
      # unrestricted nearest-point projection: on a near-closed route the global
      # nearest point to the canonical end is often a passage near the start.
      def project_endpoint(target:, polyline:, times:, from_start:)
        index = from_start ? 0 : polyline.length - 1
        endpoint = polyline[index]
        return Allure::Geometry::Projection.project(target:, polyline:, times:) if horizontal_distance(target, endpoint) > @segment.match_tolerance_meters

        segment_index = from_start ? 0 : polyline.length - 2
        fraction = from_start ? 0.0 : 1.0
        distance_along_meters = from_start ? 0.0 : polyline.each_cons(2).sum { |first, second| horizontal_distance(first, second) }
        Allure::Geometry::Projection::Result.new(
          coordinate: endpoint,
          segment_index:,
          fraction:,
          distance_meters: horizontal_distance(target, endpoint),
          distance_along_meters:,
          time: times[index]
        )
      end

      def horizontal_distance(first, second)
        Allure::Gpx::Geo.horizontal_distance(first.last, first.first, second.last, second.first)
      end
    end
  end
end
