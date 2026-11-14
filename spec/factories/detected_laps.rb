# frozen_string_literal: true

FactoryBot.define do
  factory :detected_lap do
    workout
    source { "pause" }
    sequence(:number) { |n| n }
    start_point_index { 0 }
    end_point_index { 1 }
    start_distance { 0.0 }
    end_distance { 405.0 }
    started_at { workout.started_at }
    elapsed_time { 90 }
    moving_time { 80 }
    distance { 405.0 }
    ascent { 10.0 }
    descent { 5.0 }
    average_speed { 5.0 }
    max_speed { 6.0 }
    average_pace { 180 }
    average_heart_rate { 140 }
    max_heart_rate { 160 }
    average_cadence { 85 }
    average_power { 210 }
    detector_version { Laps::Rebuild::VERSION }

    trait :loop do
      source { "loop" }
    end

    trait :route do
      source { "route" }
    end

    trait :climb do
      source { "climb" }
      distance { 1_200.0 }
      end_distance { 1_200.0 }
      elapsed_time { 600 }
      moving_time { 590 }
      ascent { 90.0 }
      descent { 2.0 }
      average_grade { 7.5 }
      max_grade { 12.0 }
      climb_score { 9.0 }
    end

    trait :descent do
      source { "descent" }
      distance { 1_400.0 }
      end_distance { 1_400.0 }
      elapsed_time { 500 }
      moving_time { 490 }
      ascent { 3.0 }
      descent { 110.0 }
      average_grade { 7.8 }
      max_grade { 11.0 }
      climb_score { 8.0 }
    end

    trait :stop do
      source { "stop" }
      distance { 0.0 }
      elapsed_time { 60 }
      moving_time { 0 }
      average_speed { 0.0 }
      average_pace { nil }
    end

    trait :speed_interval do
      source { "speed_interval" }
      distance { 2_000.0 }
      end_distance { 2_000.0 }
      elapsed_time { 300 }
      moving_time { 295 }
    end

    trait :power_interval do
      source { "power_interval" }
      distance { 3_000.0 }
      end_distance { 3_000.0 }
      elapsed_time { 600 }
      moving_time { 590 }
      average_power { 280 }
      max_power { 320 }
    end

    trait :named do
      name { "Parc de la Tête d'Or" }
    end
  end
end
