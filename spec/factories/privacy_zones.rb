# frozen_string_literal: true

FactoryBot.define do
  factory :privacy_zone do
    user
    name { "Home" }
    center { RGeo::Geographic.spherical_factory(srid: 4326).point(6.4074, 45.0710) }
    radius_meters { 100 }
    active { true }
  end
end
