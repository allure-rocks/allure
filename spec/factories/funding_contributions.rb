# frozen_string_literal: true

FactoryBot.define do
  factory :funding_contribution do
    user
    provider { "manual" }
    tier { "coffee" }
    paid_at { Time.current }

    trait :beer do
      tier { "beer" }
    end

    trait :energy do
      tier { "energy" }
    end

    trait :expired do
      paid_at { 2.years.ago }
    end

    trait :revoked do
      status { "revoked" }
    end

    trait :subscription do
      funding_subscription
      user { funding_subscription.user }
      provider { funding_subscription.provider }
      tier { funding_subscription.tier }
      sequence(:external_id) { |n| "in_#{n}" }
      starts_at { paid_at }
      expires_at { starts_at + 1.year }
    end
  end
end
