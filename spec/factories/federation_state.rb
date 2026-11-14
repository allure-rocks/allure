# frozen_string_literal: true

FactoryBot.define do
  factory :local_actor, parent: :actor, traits: [ :local ]

  factory :following do
    association :follower_actor, factory: :actor
    association :followed_actor, factory: :actor
    sequence(:uri) { |n| "https://remote.example/activities/follow-#{n}" }
    status { "pending" }
    requested_at { Time.current }

    trait :accepted do
      status { "accepted" }
      accepted_at { Time.current }
    end

    trait :rejected do
      status { "rejected" }
    end

    trait :undone do
      status { "undone" }
      undone_at { Time.current }
    end
  end

  factory :federation_peer_policy do
    sequence(:domain) { |n| "peer#{n}.example" }
    capability_profile { "public_only" }
  end

  factory :federation_domain_block do
    sequence(:domain) { |n| "blocked#{n}.example" }
  end

  factory :federation_actor_block do
    sequence(:actor_uri) { |n| "https://blocked#{n}.example/users/demo" }
  end

  factory :federation_inbox_item do
    association :recipient_actor, factory: :local_actor
    sequence(:activity_uri) { |n| "https://remote.example/activities/inbox-#{n}" }
    activity_type { "Follow" }
    actor_uri { "https://remote.example/users/demo" }
    remote_domain { Allure::Federation::Authority.domain(actor_uri) }
    raw_body_digest { "SHA-256=47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU=" }
    raw { { "id" => activity_uri, "type" => activity_type, "actor" => actor_uri } }
    status { "pending" }
  end

  factory :federation_outbox_event do
    association :actor, factory: :local_actor
    subject_type { "Actor" }
    subject_id { actor.id }
    workout_publication_id { nil }
    activity_type { "Follow" }
    object_uri { actor.uri }
    payload do
      {
        "type" => activity_type,
        "actor" => actor.uri,
        "object" => "https://remote.example/users/demo"
      }
    end
    audience { { "to" => [ "https://remote.example/users/demo" ], "cc" => [] } }

    after(:build) do |event|
      if event.subject_type == "WorkoutPublication" && event.workout_publication_id.blank?
        event.workout_publication_id = event.subject_id
      end
      if event.subject_type == "SegmentPublication" && event.segment_publication_id.blank?
        event.segment_publication_id = event.subject_id
      end
    end
  end

  factory :federation_delivery do
    association :outbox_event, factory: :federation_outbox_event
    inbox_url { "https://remote.example/inbox" }
  end

  factory :federation_delivery_recipient do
    association :delivery, factory: :federation_delivery
    actor_uri { "https://remote.example/users/demo" }
    status { "authorized" }
  end

  factory :reaction do
    association :actor, factory: :actor
    association :workout
    kind { "like" }
    audience { "public" }
    sequence(:uri) { |n| "https://remote.example/activities/like-#{n}" }

    trait :remote_note do
      association :remote_note
      workout { nil }
      audience { remote_note.audience }
    end

    trait :followers do
      audience { "followers" }
    end

    trait :beer do
      kind { "beer" }
    end
  end
end
