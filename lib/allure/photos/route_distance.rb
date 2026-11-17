# frozen_string_literal: true

module Allure
  module Photos
    # Distances along a published (sanitized) route, the only geometry a
    # shared photo position may refer to (docs/dev/PHOTOS.md). `segments` are
    # the published LineStrings' coordinates, [longitude, latitude]. The
    # distance runs over the published points in order; a gap between
    # segments adds nothing, so a receiver can measure it again from the same
    # published geometry.
    class RouteDistance
      SNAP_MAX_METRES = 200.0

      Vertex = Data.define(:longitude, :latitude, :distance)

      def initialize(segments)
        @vertices = []
        total = 0.0
        Array(segments).each do |coordinates|
          previous = nil
          Array(coordinates).each do |point|
            longitude = Float(point[0])
            latitude = Float(point[1])
            total += Gpx::Geo.haversine_distance(previous.latitude, previous.longitude, latitude, longitude) if previous
            previous = Vertex.new(longitude:, latitude:, distance: total)
            @vertices << previous
          end
        end
      end

      def empty? = @vertices.empty?

      # The nearest published point, when it lies within 200 m of the photo.
      def snap(longitude, latitude)
        best = @vertices.min_by { Gpx::Geo.haversine_distance(latitude, longitude, it.latitude, it.longitude) }
        return unless best
        return if Gpx::Geo.haversine_distance(latitude, longitude, best.latitude, best.longitude) > SNAP_MAX_METRES

        best
      end

      # The published point at a shared distance: a distance this class
      # produced lands on its own vertex.
      def at(distance)
        value = Float(distance, exception: false)
        return if value.nil? || !value.finite? || @vertices.empty?

        @vertices.min_by { (it.distance - value).abs }
      end
    end
  end
end
