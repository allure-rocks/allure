# frozen_string_literal: true

FactoryBot.define do
  factory :effort_record do
    workout
    user { workout.user }
    sport { workout.sport }
    distance_key { "km5" }
    distance_meters { 5_000.0 }
    duration_seconds { 1_200 }
    workout_started_at { workout.started_at }
  end
end
