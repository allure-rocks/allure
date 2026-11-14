# frozen_string_literal: true

FactoryBot.define do
  factory :workout_import_entry do
    batch { association :workout_import_batch }
    sequence(:position)
    sequence(:source_key) { |n| "source:#{n}" }
    sequence(:source_name) { |n| "workout-#{n}.gpx" }
    status { "queued" }
  end
end
