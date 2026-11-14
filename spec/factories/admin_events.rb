# frozen_string_literal: true

FactoryBot.define do
  factory :admin_event do
    user
    action { "domain_blocked" }
    metadata { {} }
  end
end
