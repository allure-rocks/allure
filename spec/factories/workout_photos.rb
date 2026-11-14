# frozen_string_literal: true

FactoryBot.define do
  factory :workout_photo do
    workout
    user { workout.user }
    sequence(:position)
    original_content_type { "image/jpeg" }
    bytes_total { 0 }
  end
end
