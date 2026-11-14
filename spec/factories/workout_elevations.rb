# frozen_string_literal: true

FactoryBot.define do
  factory :workout_elevation do
    workout
    status { "ready" }
    algorithm_version { WorkoutElevation::ALGORITHM_VERSION }
    provider { "https://elevation.test" }
    dataset { "mapzen" }
    samples do
      [
        { "distance" => 0.0, "latitude" => 45.0, "longitude" => 6.0, "elevation" => 2636.0 },
        { "distance" => 100.0, "latitude" => 45.001, "longitude" => 6.001, "elevation" => 2700.0 }
      ]
    end
    requests_count { 1 }
    generated_at { Time.current }
  end
end
