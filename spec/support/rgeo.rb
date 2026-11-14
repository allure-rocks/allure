# frozen_string_literal: true

module RGeoHelpers
  def geographic_factory
    @geographic_factory ||= RGeo::Geographic.spherical_factory(srid: 4326)
  end

  def geographic_point(longitude, latitude)
    geographic_factory.point(longitude, latitude)
  end

  def geographic_line_string(coordinates)
    geographic_factory.line_string(coordinates.map { |longitude, latitude| geographic_point(longitude, latitude) })
  end
end

RSpec.configure do |config|
  config.include RGeoHelpers
end
