# frozen_string_literal: true

FactoryBot.define do
  factory :best_effort do
    workout
    user { workout.user }
    sport { workout.sport }
    distance_key { "km5" }
    distance_meters { 5_000.0 }
    duration_seconds { 1_200 }
    started_at { workout.started_at }
    start_offset_meters { 0.0 }
    end_offset_meters { 5_000.0 }
  end
end
