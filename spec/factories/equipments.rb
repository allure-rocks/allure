# frozen_string_literal: true

FactoryBot.define do
  factory :equipment do
    user
    equipment_type
    sequence(:label) { |n| "Gear #{n}" }
    description { "Test gear" }
    is_active { true }
    total_distance { 0 }
    total_duration { 0 }
    total_moving { 0 }
    total_workouts { 0 }

    trait :inactive do
      is_active { false }
    end
  end
end
