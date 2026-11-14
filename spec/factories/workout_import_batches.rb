# frozen_string_literal: true

FactoryBot.define do
  factory :workout_import_batch do
    user
    sport
    status { "queued" }
    notes { nil }
  end
end
