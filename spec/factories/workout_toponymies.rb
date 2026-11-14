# frozen_string_literal: true

FactoryBot.define do
  factory :workout_toponymy do
    workout
    status { "ready" }
    algorithm_version { Workouts::ToponymyEnricher::ALGORITHM_VERSION }
    provider { "https://geocoding.test" }
    samples { [] }
    start_place { { "name" => "Valmorin", "kind" => "village" } }
    finish_place { { "name" => "Rochelune", "kind" => "city" } }
    markers do
      [ { "distance" => 20_000.0, "elevation" => 250.0, "name" => "Cimefroide", "kind" => "town", "rank" => 1 } ]
    end
    sampled_points_count { 30 }
    generated_at { Time.current }
  end
end
