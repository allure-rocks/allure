# frozen_string_literal: true

FactoryBot.define do
  factory :notification do
    user
    kind { "follow_request" }
    payload { {} }
    actor { association(:actor) }
    subject { association(:following, follower_actor: actor, followed_actor: association(:actor)) }

    trait :accepted do
      kind { "follow_accepted" }
    end

    # The actorless activation notice (docs/dev/DELAYED-PUBLISHING.md).
    trait :publication_activated do
      kind { "publication_activated" }
      actor { nil }
      subject { association(:workout_publication) }
      payload { { "audience" => "public" } }
    end
  end
end
