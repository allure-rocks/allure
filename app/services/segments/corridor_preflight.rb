# frozen_string_literal: true

module Segments
  # The PostGIS corridor test shared by shared-leaderboard eligibility (a third
  # party's location history must not be listed) and the owner-facing preflight
  # before a course is shared (PLAN_SEGMENTS_FEDERATION.md §5.2). A segment
  # corridor is geometry widened by its match tolerance; privacy zones are
  # never subtracted from it, so the preflight is a consent gate, not filtering.
  class CorridorPreflight
    def self.for_geometry(user:, geom:, tolerance_meters:)
      user.privacy_zones.active.where(
        "ST_DWithin(?, privacy_zones.center, privacy_zones.radius_meters + ?)",
        geom, tolerance_meters
      )
    end

    def self.intersecting_zones(segment)
      for_geometry(
        user: segment.user,
        geom: segment.geom,
        tolerance_meters: segment.match_tolerance_meters
      )
    end

    def self.intersects?(segment)
      return false if segment.geom.blank?

      intersecting_zones(segment).exists?
    end
  end
end
