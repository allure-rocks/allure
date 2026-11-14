# frozen_string_literal: true

FactoryBot.define do
  factory :workout_bulk_operation do
    user
    operation { "delete" }
    status { "draft" }
    parameters { {} }
  end

  factory :workout_bulk_operation_item do
    operation factory: :workout_bulk_operation
    workout
    position { 0 }
    status { "queued" }
  end
end
