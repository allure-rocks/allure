# frozen_string_literal: true

module Allure
  module Virtual
    # A virtual world's real-world anchor (PLAN_VIRTUAL.md). The platform
    # renders a fictional course at a real location, so the workout's geometry
    # sits at the anchor and the world can be recognised from the start point.
    # `radius_m` is the generous bound that contains every published route of
    # the world, not the size of any single course.
    #
    # `basemap` is the world's published map image when the world has one; the
    # image's own rectangle is authoritative for drawing it, while the radius
    # stays what recognises the world from a recorded point.
    Venue = Data.define(:key, :name, :longitude, :latitude, :radius_m, :basemap) do
      def initialize(key:, name:, longitude:, latitude:, radius_m:, basemap: nil)
        super(
          key: key.to_s.freeze,
          name: name.to_s.freeze,
          longitude: longitude.to_f,
          latitude: latitude.to_f,
          radius_m: radius_m.to_f,
          basemap: basemap && Basemap.new(**basemap)
        )
      end

      def distance_to(longitude:, latitude:)
        Allure::Gpx::Geo.horizontal_distance(latitude, longitude, self.latitude, self.longitude)
      end
    end
  end
end
