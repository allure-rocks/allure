# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    sequence(:username) { |n| "rider#{n}" }
    sequence(:email_address) { |n| "rider#{n}@allure.test" }
    password { "allure-test-password" }
    password_confirmation { "allure-test-password" }
    display_name { "Rider" }
    locale { "fr" }
    time_zone { "Europe/Paris" }
    profile_statistics_audience { "none" }
    profile_records_audience { "none" }

    # An enrolled authenticator app (docs/dev/AUTH.md); the global
    # `sign_in_as` answers the second step with its current code.
    trait :with_totp do
      otp_secret { ROTP::Base32.random }
      otp_enrolled_at { Time.current }
    end
  end
end
