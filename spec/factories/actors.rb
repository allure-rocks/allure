# frozen_string_literal: true

require "openssl"

FactoryBot.define do
  factory :actor do
    sequence(:uri) { |n| "https://remote.example/users/remote#{n}" }
    local { false }
    capability_profile { "unknown" }

    trait :local do
      local { true }
      association :user

      after(:build) do |actor|
        key = OpenSSL::PKey::RSA.generate(2048)
        actor.uri = actor.user.actor_uri
        actor.handle = actor.user.handle
        actor.display_name = actor.user.display_name
        actor.public_key_id = actor.user.key_id
        actor.public_key_pem = key.public_key.to_pem
        actor.private_key_ciphertext = key.to_pem
        actor.inbox_url = Allure::Federation.config.inbox_uri(actor.user.username)
      end
    end
  end
end
