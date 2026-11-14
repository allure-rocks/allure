# frozen_string_literal: true

FactoryBot.define do
  factory :publishing_profile do
    user
    name { "Public profile" }
    built_in_key { "public" }
    audience { "public" }
    settings { PublishingProfile::DEFAULT_SETTINGS.deep_dup }
    position { 0 }

    trait :followers do
      name { "Followers profile" }
      built_in_key { "followers" }
      audience { "followers" }
    end

    trait :custom do
      name { "Custom profile" }
      built_in_key { nil }
    end

    trait :without_endpoint_masks do
      settings do
        PublishingProfile::DEFAULT_SETTINGS.merge(
          "mask_start" => false,
          "mask_finish" => false
        )
      end
    end
  end
end
