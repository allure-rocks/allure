# frozen_string_literal: true

module Allure
  module Laps
    # Shared projection of a climb or descent found by the elevation segmenter
    # onto the point stream. The subclass only chooses the source and how the
    # elevation profile is fed to the segmenter.
    class ElevationDetector
      # A recording segment boundary is a pause or a teleport. The ground is
      # continuous across a pause — the athlete stood still and resumed where
      # they stopped — but not across a teleport, where the platform moved them
      # (docs/dev/VIRTUAL-PLATFORMS.md). The threshold is the teleport's own minimum
      # step: a boundary whose positions jump that far starts a new run of
      # ground, so a climb never spans it.
      SEGMENT_JUMP_METRES = 200.0

      def initialize(points:, stopped_speed_threshold_km_h: 0.0, elevation_filter: nil)
        @points = points
        @stopped_speed_threshold_km_h = stopped_speed_threshold_km_h
        @elevation_filter = elevation_filter
      end

      def call
        return [] if @points.length < 4

        runs.flat_map do |offset, points|
          profile = elevation_profile(points)
          next [] if profile.length < 4

          Allure::Climbs::Segmenter.new(points: transformed(profile), profile: Allure::Climbs::Segmenter::LAP)
            .call.filter_map { |climb| build(climb, offset, points) }
        end
      end

      private

      def source
        raise NotImplementedError
      end

      def transformed(profile) = profile

      def elevation_profile(points)
        points.filter_map do |point|
          next unless point.elevation.is_a?(Numeric) && point.elevation.finite?

          { distance: point.distance.to_f, elevation: point.elevation.to_f, index: point.index }
        end
      end

      # Consecutive points over one continuous run of ground, each with the
      # offset of its first point in the whole stream. Only a recording segment
      # boundary can break the run, and only when the positions jump: within one
      # segment a long step is just a sparse sample, not a discontinuity.
      def runs
        runs = []
        start = 0
        @points.each_with_index do |point, index|
          next if index.zero? || !teleport_boundary?(@points[index - 1], point)

          runs << [ start, @points[start...index] ]
          start = index
        end
        runs << [ start, @points[start..] ]
        runs
      end

      def teleport_boundary?(previous, current)
        return false if previous.segment_index == current.segment_index
        return false if previous.longitude.nil? || previous.latitude.nil? ||
          current.longitude.nil? || current.latitude.nil?

        Allure::Gpx::Geo.horizontal_distance(
          previous.latitude, previous.longitude, current.latitude, current.longitude
        ) >= SEGMENT_JUMP_METRES
      end

      def build(climb, offset, points)
        start_index = nearest_index(climb.start_distance, points) + offset
        end_index = nearest_index(climb.end_distance, points) + offset
        return if end_index <= start_index

        metrics = Allure::Laps::Metrics.new(
          points: @points[start_index..end_index],
          stopped_speed_threshold_km_h: @stopped_speed_threshold_km_h,
          elevation_filter: @elevation_filter
        ).call
        return unless metrics

        Allure::Laps::Lap.new(
          source:,
          start_point_index: start_index,
          end_point_index: end_index,
          start_distance: @points[start_index].distance,
          end_distance: @points[end_index].distance,
          started_at: metrics.started_at,
          elapsed_time: metrics.elapsed_time,
          moving_time: metrics.moving_time,
          distance: metrics.distance,
          ascent: metrics.ascent,
          descent: metrics.descent,
          average_speed: metrics.average_speed,
          average_pace: metrics.average_pace,
          max_speed: metrics.max_speed,
          average_heart_rate: metrics.average_heart_rate,
          max_heart_rate: metrics.max_heart_rate,
          average_cadence: metrics.average_cadence,
          average_power: metrics.average_power,
          max_power: metrics.max_power,
          average_grade: (climb.average_grade * 100).round(2),
          max_grade: (climb.max_grade * 100).round(2),
          climb_score: ((climb.length / 1_000.0) * climb.average_grade * 100).round(2)
        )
      end

      def nearest_index(distance, points)
        points.each_index.min_by { |index| (points[index].distance.to_f - distance).abs }
      end
    end
  end
end
