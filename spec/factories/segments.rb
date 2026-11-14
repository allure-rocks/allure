# frozen_string_literal: true

FactoryBot.define do
  factory :segment do
    user
    sport
    kind { "segment" }
    name { "Col du Test" }
    description { "A reusable test segment" }
    geom do
      factory = RGeo::Geographic.spherical_factory(srid: 4326)
      factory.line_string([ factory.point(6.4074, 45.0710), factory.point(6.4092, 45.0728) ])
    end
    start_point { RGeo::Geographic.spherical_factory(srid: 4326).point(6.4074, 45.0710) }
    end_point { RGeo::Geographic.spherical_factory(srid: 4326).point(6.4092, 45.0728) }
    bounds { [ 45.0710, 6.4074, 45.0728, 6.4092 ] }
    distance { 250.0 }
    ascent { 12.0 }
    descent { 4.0 }
    min_elevation { 100.0 }
    max_elevation { 112.0 }
    average_grade { 4.8 }
    signature { Array.new(64, 0.0) }
    match_tolerance_meters { 25 }
    visibility { "private" }
    active { true }
    efforts_count { 0 }
    athletes_count { 0 }
    matcher_version { Allure::Segments::Matcher::VERSION }

    trait :route do
      kind { "route" }
    end

    trait :loop do
      kind { "loop" }
      name { "Morning ride loop" }
    end
  end
end
