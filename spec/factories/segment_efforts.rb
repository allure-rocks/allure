# frozen_string_literal: true

FactoryBot.define do
  factory :segment_effort do
    workout
    segment { association :segment, user: workout.user, sport: workout.sport }
    user { workout.user }
    sport { workout.sport }
    occurrence_index { 0 }
    started_at { workout.started_at }
    elapsed_time { 50 }
    moving_time { 45 }
    distance { 250.0 }
    ascent { 12.0 }
    descent { 4.0 }
    average_speed { 5.0 }
    average_pace { 200 }
    average_heart_rate { 140 }
    max_heart_rate { 160 }
    average_cadence { 80 }
    average_power { 200 }
    max_power { 250 }
    start_offset_meters { 0.0 }
    start_point_index { 0 }
    end_point_index { 1 }
    deviation_meters { 5.0 }
    personal_best { false }
    anonymous { false }
    matcher_version { Allure::Segments::Matcher::VERSION }
  end
end
