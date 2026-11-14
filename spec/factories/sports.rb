# frozen_string_literal: true

FactoryBot.define do
  factory :sport do
    sequence(:slug) { |n| "test_sport_#{n}" }
    sequence(:label) { |n| "Test Sport #{n}" }
    colour_group { "other" }
    active { true }
    stopped_speed_threshold { 1.0 }
    pace_speed_display { "speed" }
    cadence_unit { nil }
    records_elevation { true }
    records_power { false }
    virtual { false }
    position { Sport.maximum(:position).to_i + 1 }
  end
end
