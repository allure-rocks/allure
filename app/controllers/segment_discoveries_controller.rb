# frozen_string_literal: true

# The discover map (PLAN_SEGMENTS.md §8.4): every course the viewer may see —
# the readable shared ones and their own, private ones included — inside the
# requested viewport, as a sanitized GeoJSON FeatureCollection. Facts only —
# name, sport, distance, participant count and the course URL, all formatted
# server-side for the viewer's locale and unit system — never an effort, an
# athlete or a source workout. Denials stay implicit: the scope simply never
# matches a course the viewer may not see.
class SegmentDiscoveriesController < ApplicationController
  def show
    bbox = parse_bbox
    return head :bad_request unless bbox

    rows = Segments::DiscoveryQuery.new(viewer: current_user, bbox:).call

    response.headers["Cache-Control"] = "private, no-store"
    render json: { type: "FeatureCollection", features: rows.map { |row| feature(row) } },
           content_type: "application/geo+json"
  end

  private

  # A malformed or nonsensical viewport is a client error, never a silent
  # PostGIS failure. The envelope is bounded to the real coordinate space.
  def parse_bbox
    values = params[:bbox].to_s.split(",").map { |value| Float(value, exception: false) }
    return nil unless values.length == 4 && values.all? { |value| value.is_a?(Float) && value.finite? }

    west, south, east, north = values
    return nil unless west.between?(-180, 180) && east.between?(-180, 180)
    return nil unless south.between?(-90, 90) && north.between?(-90, 90)
    return nil unless west < east && south < north

    values
  end

  def feature(row)
    {
      type: "Feature",
      geometry: row.geometry,
      properties: {
        name: row.name,
        sport: row.sport ? helpers.sport_display_name(row.sport) : helpers.t("segments.details.all_sports"),
        distance: helpers.format_distance(row.distance, unit_system: current_user.unit_system),
        participants: helpers.t("segments.card.participants", count: row.participants_count),
        url: helpers.segment_path(Allure::ShortId.encode(row.uuid))
      }
    }
  end
end
