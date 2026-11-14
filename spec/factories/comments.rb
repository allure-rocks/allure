# frozen_string_literal: true

FactoryBot.define do
  # A local account's comment on a local workout's thread (PLAN_COMMENTS.md
  # §3.1). Its URI is minted from its own identifier, like every local object.
  factory :comment do
    workout
    association :actor, factory: :local_actor
    sequence(:in_reply_to_uri) { |n| "#{Allure::Federation.config.base_url}/api/v1/trail/thread-#{n}" }
    audience { "public" }
    body { "Belle sortie !" }
    published_at { Time.current }

    trait :reply do
      parent { association :comment, workout: }
      in_reply_to_uri { parent.uri }
    end

    trait :deleted do
      status { "deleted" }
      deleted_at { Time.current }
    end

    trait :removed do
      status { "removed" }
      removal_reason { "owner" }
      removed_at { Time.current }
    end
  end
end
