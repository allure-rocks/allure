# frozen_string_literal: true

FactoryBot.define do
  factory :equipment_type do
    sequence(:slug) { |n| "type-#{n}" }
    sequence(:label) { |n| "Equipment type #{n}" }
    is_active { true }
  end
end
