# frozen_string_literal: true

FactoryBot.define do
  factory :remote_note do
    association :actor, factory: :actor
    sequence(:object_uri) { |n| "https://remote.example/api/v1/trail/remote-#{n}" }
    sequence(:activity_uri) { |n| "https://remote.example/api/v1/trail/remote-#{n}/activities/create-#{n}" }
    received_at { Time.current }
    audience { "public" }
    title { "Remote hike" }
    description { "A remote hike" }
    content_html { "Remote hike" }
    sport_label { "Hiking" }
    started_at { Time.utc(2026, 8, 26, 12) }
    published_at { Time.utc(2026, 8, 26, 12) }
    metrics { { "distance" => 23_064.64, "duration" => 22_345.0 } }
    representation do
      {
        "title" => title,
        "description" => description,
        "sport_label" => sport_label,
        "started_at" => started_at.iso8601,
        "metrics" => metrics
      }
    end
    route_metadata { {} }
    raw { {} }
    warnings { [] }
    source_domain { Allure::Federation::Authority.domain(actor.uri) }

    trait :deleted do
      status { "deleted" }
      deleted_at { Time.current }
      location_data_purged_at { Time.current }
      representation do
        {
          "title" => title,
          "description" => description,
          "sport_label" => sport_label,
          "started_at" => started_at.iso8601,
          "metrics" => metrics,
          "redacted" => true
        }
      end
      route_metadata { { "redacted" => true } }
    end
  end

  factory :remote_note_recipient do
    association :remote_note
    association :recipient_actor, factory: :local_actor
    status { "active" }

    trait :withdrawn do
      status { "withdrawn" }
      withdrawn_at { Time.current }
      withdrawal_reason { "deleted" }
    end
  end

  factory :remote_note_attachment do
    association :remote_note
    sequence(:remote_url) { |n| "https://remote.example/api/v1/trail/remote-#{n}/media/gpx" }
    kind { "gpx" }
    media_type { "application/xml+gpx" }
    status { "pending" }
  end
end
