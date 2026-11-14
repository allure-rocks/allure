# frozen_string_literal: true

FactoryBot.define do
  factory :funding_subscription do
    user
    provider { "stripe" }
    sequence(:external_id) { |n| "sub_#{n}" }
    sequence(:customer_id) { |n| "cus_#{n}" }
    tier { "beer" }
    status { "active" }
    synced_at { Time.current }
  end
end
