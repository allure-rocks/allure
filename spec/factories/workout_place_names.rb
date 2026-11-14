# frozen_string_literal: true

FactoryBot.define do
  factory :workout_place_name do
    workout
    user { workout.user }
    name { "Rochelune" }
    kind { "city" }
    sequence(:position) { |n| n - 1 }
  end
end
