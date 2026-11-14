# frozen_string_literal: true

# A complete track shared by the recurring-route specs: three points, 250 m,
# from the workout factory's default start point. The same points on several
# recordings are exactly what the route matcher accepts.
module RouteSuggestionHelpers
  TRACK = [
    { "t" => 0, "d" => 0.0, "lat" => 45.0710, "lon" => 6.4074, "ele" => 100.0 },
    { "t" => 30, "d" => 125.0, "lat" => 45.0719, "lon" => 6.4083, "ele" => 105.0 },
    { "t" => 60, "d" => 250.0, "lat" => 45.0728, "lon" => 6.4092, "ele" => 110.0 }
  ].freeze

  def route_suggestion_track
    TRACK
  end

  def route_suggestion_factory
    RGeo::Geographic.spherical_factory(srid: 4326)
  end

  def route_suggestion_point(point)
    route_suggestion_factory.point(point.fetch("lon"), point.fetch("lat"))
  end

  def route_suggestion_line(points)
    route_suggestion_factory.line_string(points.map { |point| route_suggestion_point(point) })
  end

  def route_suggestion_bounds(points)
    latitudes = points.map { |point| point.fetch("lat") }
    longitudes = points.map { |point| point.fetch("lon") }
    [ latitudes.min, longitudes.min, latitudes.max, longitudes.max ]
  end

  def route_suggestion_recording(user:, sport:, started_at: Time.zone.parse("2026-08-23 06:00:00"),
                                 points: route_suggestion_track)
    workout = create(
      :workout,
      user:,
      sport:,
      started_at:,
      distance: points.last.fetch("d"),
      start_point: route_suggestion_point(points.first),
      bounds: route_suggestion_bounds(points)
    )
    create(
      :track_segment,
      workout:,
      position: 0,
      distance: points.last.fetch("d"),
      points:,
      geom: route_suggestion_line(points)
    )
    workout
  end
end

RSpec.configure do |config|
  config.include RouteSuggestionHelpers
end
