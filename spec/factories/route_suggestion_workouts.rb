# frozen_string_literal: true

FactoryBot.define do
  factory :route_suggestion_workout do
    route_suggestion
    workout { association(:workout, user: route_suggestion.user, sport: route_suggestion.sport) }
  end
end
