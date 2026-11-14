# frozen_string_literal: true

FactoryBot.define do
  factory :funding_reversal do
    funding_contribution
    provider { funding_contribution.provider == "manual" ? "stripe" : funding_contribution.provider }
    sequence(:external_id) { |n| "re_#{n}" }
    kind { "refund" }
    status { "succeeded" }
    amount_cents { 100 }
    currency { "EUR" }
    reported_at { Time.current }

    trait :failed do
      status { "failed" }
    end

    trait :dispute do
      kind { "dispute" }
      sequence(:external_id) { |n| "dp_#{n}" }
      status { "open" }
    end

    trait :won do
      dispute
      status { "won" }
    end

    trait :lost do
      dispute
      status { "lost" }
    end
  end
end
