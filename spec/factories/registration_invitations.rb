# frozen_string_literal: true

FactoryBot.define do
  factory :registration_invitation do
    email_address { "invitee@allure.test" }
    expires_at { 7.days.from_now }
    token_digest { Digest::SHA256.hexdigest(SecureRandom.urlsafe_base64(32)) }

    trait :accepted do
      accepted_at { Time.current }
    end
  end
end
