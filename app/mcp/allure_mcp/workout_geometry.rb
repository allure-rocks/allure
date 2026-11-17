# frozen_string_literal: true

module AllureMcp
  # A workout's track for an AI assistant, at the token's location level
  # (docs/dev/MCP.md): nothing at `none`; at `filtered`, every point inside an
  # active privacy zone removed, start and finish included (no endpoint
  # exemption, unlike a publication profile); at `raw`, the recorded points.
  # Either way thinned evenly to `max_points`, recording segments kept apart.
  class WorkoutGeometry
    DEFAULT_POINTS = 300
    MAX_POINTS = 2_000
    PRECISION = 5

    def initialize(workout, level:, max_points: DEFAULT_POINTS)
      @workout = workout
      @level = level
      @max_points = max_points.to_i.clamp(2, MAX_POINTS)
    end

    def call
      return { level: "none", available: false, reason: "token_location_level_none" } if @level == "none"

      segments = source_segments
      return { level: @level, available: false, reason: "no_track" } if segments.empty?

      zones = @level == "filtered" ? @workout.user.privacy_zones.active.map(&:to_value) : []
      if zones.any?
        filtered = Allure::Federation::Privacy::ZoneFilter.new(segments:, zones:).call
        return { level: @level, available: false, reason: "hidden_by_privacy_zones" } unless filtered.usable?

        segments = filtered.segments.select { it.length >= 2 }
      end

      thinned = thin(segments)
      {
        level: @level,
        available: true,
        privacy_zones_applied: zones.size,
        type: "MultiLineString",
        coordinate_order: "longitude, latitude",
        coordinates: thinned.map { |segment| segment.map { |lon, lat| [ lon.round(PRECISION), lat.round(PRECISION) ] } },
        points_returned: thinned.sum(&:size)
      }
    end

    private

    def source_segments
      longitude = Allure::Gpx::PointSerializer::KEY_LONGITUDE
      latitude = Allure::Gpx::PointSerializer::KEY_LATITUDE
      @workout.track_segments.filter_map do |segment|
        points = Array(segment.points).filter_map do |point|
          [ Float(point[longitude]), Float(point[latitude]) ] if point.is_a?(Hash) && point[longitude] && point[latitude]
        end
        points if points.length >= 2
      end
    end

    # Each segment keeps a share of the budget proportional to its length,
    # with its first and last points.
    def thin(segments)
      total = segments.sum(&:size)
      return segments if total <= @max_points

      segments.map do |segment|
        budget = [ (segment.size * @max_points.fdiv(total)).floor, 2 ].max
        next segment if segment.size <= budget

        step = (segment.size - 1).fdiv(budget - 1)
        Array.new(budget) { segment[(it * step).round] }
      end
    end
  end
end
