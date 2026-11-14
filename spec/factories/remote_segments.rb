# frozen_string_literal: true

FactoryBot.define do
  factory :remote_segment do
    association :actor, factory: :actor
    sequence(:object_uri) { |n| "https://remote.example/api/v1/segment/remote-#{n}" }
    sequence(:activity_uri) { |n| "https://remote.example/api/v1/segment/remote-#{n}/activities/create-#{n}" }
    received_at { Time.current }
    audience { "public" }
    name { "Remote climb" }
    description { "A remote climb" }
    content_html { "Remote climb" }
    sport_label { "Cycling" }
    kind { "segment" }
    distance { 2_500.0 }
    ascent { 180.0 }
    descent { 12.0 }
    average_grade { 7.2 }
    published_at { Time.utc(2026, 8, 26, 12) }
    representation do
      {
        "name" => name,
        "description" => description,
        "sport_slug" => "cycling",
        "kind" => "segment",
        "distance" => distance,
        "ascent" => ascent,
        "descent" => descent,
        "average_grade" => average_grade,
        "match_tolerance" => 25,
        "location" => { "longitude" => 6.4, "latitude" => 45.0 }
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
      name { "" }
      representation { { "redacted" => true } }
      route_metadata { { "redacted" => true } }
    end
  end

  factory :remote_segment_recipient do
    association :remote_segment
    association :recipient_actor, factory: :local_actor
    status { "active" }

    trait :withdrawn do
      status { "withdrawn" }
      withdrawn_at { Time.current }
      withdrawal_reason { "deleted" }
    end
  end

  factory :remote_segment_attachment do
    association :remote_segment
    sequence(:remote_url) { |n| "https://remote.example/api/v1/segment/remote-#{n}/media/gpx" }
    kind { "gpx" }
    media_type { "application/xml+gpx" }
    status { "pending" }
  end
end
