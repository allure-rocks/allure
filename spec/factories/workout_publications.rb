# frozen_string_literal: true

FactoryBot.define do
  factory :workout_publication do
    transient do
      # A snapshot whose profile closed comments (PLAN_COMMENTS.md §6.4).
      comments_closed { false }
    end

    workout
    actor do
      workout.user.actor || association(:local_actor, user: workout.user)
    end
    publishing_profile { association :publishing_profile, user: workout.user }
    privacy_zone_fingerprint { "0" * 64 }
    route_metadata { { "bounds" => [ 45.0, 6.4, 45.1, 6.5 ], "segments_count" => 1 } }
    representation do
      {
        "sport_slug" => workout.sport.slug,
        "started_at" => workout.started_at.iso8601(6),
        "metrics" => {},
        "track" => {
          "type" => "FeatureCollection",
          "features" => [
            {
              "type" => "Feature",
              "geometry" => { "type" => "LineString", "coordinates" => [ [ 6.4, 45.0 ], [ 6.5, 45.1 ] ] },
              "properties" => { "segment_index" => 0 }
            }
          ]
        }
      }.merge(comments_closed ? { "comments_closed" => true } : {})
    end
    filtered_points_count { 2 }
    has_route { true }

    trait :with_followers do
      publishing_profile { association :publishing_profile, :followers, user: workout.user }
    end

    # A publication inside its safety delay: frozen but not yet shared.
    trait :scheduled do
      status { "scheduled" }
      scheduled_for { 1.day.from_now }
    end
  end
end
