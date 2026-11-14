# frozen_string_literal: true

FactoryBot.define do
  factory :lap do
    workout
    sequence(:number) { |n| n }
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
    lap_trigger { "manual" }

    trait :sparse do
      # A minimal lap: only the fields a GPX `<lap>` reliably provides.
      distance { 405.0 }
      ascent { nil }
      descent { nil }
      max_speed { nil }
      average_pace { nil }
      average_heart_rate { nil }
      max_heart_rate { nil }
      average_cadence { nil }
      average_power { nil }
      lap_trigger { nil }
    end
  end
end
