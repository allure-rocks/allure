# frozen_string_literal: true

module Laps
  # Rebuilds every derived smart lap for one workout in a single transaction:
  # loop and route laps projected from existing efforts, one pause lap per
  # recording segment, climbs and descents from the elevation profile, stops,
  # and speed/power intervals. Tracks are immutable, so a re-run is
  # deterministic and idempotent. Overlapping laps keep the higher-precedence
  # source: route, then loop, then pause. Every other source lives in its own
  # tab and is only de-overlapped within itself.
  class Rebuild
    VERSION = 5
    PRECEDENCE = %w[route loop pause].freeze
    INDEPENDENT_SOURCES = %w[climb descent stop speed_interval power_interval].freeze

    def initialize(workout:, points: nil)
      @workout = workout
      @points = points
    end

    def call
      points = @points || point_stream
      laps = effort_laps(points)
      laps.concat(Allure::Laps::PauseDetector.new(segments: @workout.track_segments).call)
      laps.concat(elevation_laps(points))
      laps.concat(stops(points))
      laps.concat(speed_intervals(points))
      laps.concat(power_intervals(points))

      persist(select_non_overlapping(laps))
      Laps::Naming.new(workout: @workout).call
      @workout.detected_laps.reset
    end

    private

    def point_stream
      Allure::Segments::PointStream.new(
        segments: @workout.track_segments,
        workout_started_at: @workout.started_at
      ).call
    end

    def effort_laps(points)
      efforts = @workout.segment_efforts
        .joins(:segment)
        .where(segments: { kind: %w[loop route] })
        .includes(:segment)
        .order(:started_at, :id)

      efforts.group_by(&:segment_id).flat_map do |_segment_id, group|
        next [] if group.first.segment.kind == "route" && group.length < 2

        group.filter_map { |effort| effort_lap(effort, points) }
      end
    end

    def effort_lap(effort, points)
      start_point = points[effort.start_point_index]
      end_point = points[effort.end_point_index]
      return unless start_point && end_point

      Allure::Laps::Lap.new(
        source: effort.segment.kind,
        start_point_index: effort.start_point_index,
        end_point_index: effort.end_point_index,
        start_distance: start_point.distance,
        end_distance: end_point.distance,
        started_at: effort.started_at,
        elapsed_time: effort.elapsed_time,
        moving_time: effort.moving_time,
        distance: effort.distance,
        ascent: effort.ascent,
        descent: effort.descent,
        average_speed: effort.average_speed,
        average_pace: effort.average_pace,
        average_heart_rate: effort.average_heart_rate,
        max_heart_rate: effort.max_heart_rate,
        average_cadence: effort.average_cadence,
        average_power: effort.average_power,
        max_power: effort.max_power,
        segment_effort_id: effort.id
      )
    end

    def elevation_laps(points)
      return [] unless @workout.sport.records_elevation

      threshold = @workout.sport.stopped_speed_threshold
      Allure::Laps::ClimbDetector.new(points:, stopped_speed_threshold_km_h: threshold, elevation_filter: @workout.elevation_filter).call +
        Allure::Laps::DescentDetector.new(points:, stopped_speed_threshold_km_h: threshold, elevation_filter: @workout.elevation_filter).call
    end

    def stops(points)
      return [] unless movement_evidence?(points)

      Allure::Laps::StopDetector.new(
        points:,
        stopped_speed_threshold_km_h: @workout.sport.stopped_speed_threshold,
        elevation_filter: @workout.elevation_filter
      ).call
    end

    def speed_intervals(points)
      return [] unless movement_evidence?(points)

      Allure::Laps::SpeedIntervalDetector.new(
        points:,
        colour_group: @workout.sport.colour_group,
        stopped_speed_threshold_km_h: @workout.sport.stopped_speed_threshold,
        # A positionless recording has no gradient, so no grade-adjusted pace
        # exists anywhere in its derived laps (docs/dev/NO-GPS.md).
        grade_adjusted_pace: grade_adjusted_pace?
      ).call
    end

    # A stop or a speed interval is a statement about movement. A positionless
    # recording whose file recorded neither a speed reading nor a distance
    # step (a duration-only session, docs/dev/NO-GPS.md) has no movement
    # signal at all: its zero speeds are unknown speeds, not a 45-minute
    # standstill.
    def movement_evidence?(points)
      return true if points.any? { |point| !point.speed.nil? }

      points.each_cons(2).any? { |previous, current| current.distance.to_f > previous.distance.to_f }
    end

    def power_intervals(points)
      return [] unless @workout.sport.records_power

      Allure::Laps::PowerIntervalDetector.new(
        points:,
        colour_group: @workout.sport.colour_group,
        stopped_speed_threshold_km_h: @workout.sport.stopped_speed_threshold,
        grade_adjusted_pace: grade_adjusted_pace?
      ).call
    end

    # Grade-adjusted pace needs a gradient, which only a positioned recording
    # has (docs/dev/NO-GPS.md).
    def grade_adjusted_pace?
      @workout.sport.grade_adjusted_pace? && @workout.positioned?
    end

    def select_non_overlapping(laps)
      kept = []
      PRECEDENCE.each do |source|
        laps.select { |lap| lap.source == source }.sort_by(&:start_distance).each do |lap|
          next if kept.any? { |other| lap.overlaps?(other) }

          kept << lap
        end
      end
      INDEPENDENT_SOURCES.each do |source|
        kept.concat(select_disjoint(laps.select { |lap| lap.source == source }))
      end
      kept.sort_by { |lap| [ lap.start_distance, lap.end_distance ] }
    end

    def select_disjoint(source_laps)
      source_laps.sort_by(&:start_distance).each_with_object([]) do |lap, kept|
        next if kept.any? { |other| lap.overlaps?(other) }

        kept << lap
      end
    end

    def persist(laps)
      DetectedLap.transaction do
        @workout.detected_laps.delete_all
        counters = Hash.new(0)
        laps.each do |lap|
          counters[lap.source] += 1
          @workout.detected_laps.create!(
            lap.to_h.slice(*DetectedLap.column_names.map(&:to_sym))
              .merge(number: counters[lap.source], detector_version: VERSION)
          )
        end
      end
    end
  end
end
