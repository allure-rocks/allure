# frozen_string_literal: true

FactoryBot.define do
  factory :track_segment do
    workout
    sequence(:position) { |n| n - 1 }
    started_at { workout.started_at }
    duration { 60 }
    moving_time { 50 }
    pause_time { 10 }
    distance { 250.0 }
    ascent { 12.0 }
    descent { 4.0 }
    min_elevation { 100.0 }
    max_elevation { 112.0 }
    average_speed { 5.0 }
    max_speed { 6.0 }
    average_pace { 200 }
    best_pace { 167 }
    points do
      [
        { "t" => 0, "d" => 0.0, "lat" => 45.0710, "lon" => 6.4074, "ele" => 100.0 },
        { "t" => 60, "d" => 250.0, "lat" => 45.0728, "lon" => 6.4092, "ele" => 112.0 }
      ]
    end
    points_count { points.length }
    geom do
      factory = RGeo::Geographic.spherical_factory(srid: 4326)
      factory.line_string(points.map { |point| factory.point(point.fetch("lon"), point.fetch("lat")) })
    end

    # A segment of a positionless recording: coordinates absent from every
    # point, no geometry (PLAN_NO_GPS.md §5).
    trait :unpositioned do
      points do
        [
          { "t" => 0, "d" => 0.0, "hr" => 120, "pw" => 190 },
          { "t" => 60, "d" => 250.0, "hr" => 132, "pw" => 210 }
        ]
      end
      geom { nil }
      ascent { 0.0 }
      descent { 0.0 }
      min_elevation { nil }
      max_elevation { nil }
    end
  end
end
