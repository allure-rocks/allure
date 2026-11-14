# frozen_string_literal: true

FactoryBot.define do
  factory :workout_participation do
    workout
    association :participant_actor, factory: :local_actor
    kind { "credit" }
    origin { "invitation" }
    owner_confirmed_at { Time.current }
    participant_confirmed_at { Time.current }

    trait :pending do
      participant_confirmed_at { nil }
    end

    trait :declined do
      participant_confirmed_at { nil }
      declined_at { Time.current }
    end

    trait :withdrawn do
      withdrawn_at { Time.current }
    end

    trait :link do
      kind { "link" }
      participant_workout { association(:workout, user: participant_actor.user) }
    end
  end
end
