# frozen_string_literal: true

FactoryBot.define do
  factory :route_suggestion do
    user
    sport
    reference_workout { association(:workout, user:, sport:) }
    status { "pending" }

    trait :dismissed do
      status { "dismissed" }
    end

    trait :accepted do
      status { "accepted" }
      segment { association(:segment, :route, user:, sport:) }
    end
  end
end
