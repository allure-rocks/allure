# frozen_string_literal: true

FactoryBot.define do
  factory :workout do
    user
    sport
    title { "Morning ride" }
    started_at { Time.zone.parse("2026-08-23 06:00:00") }
    duration { 60 }
    moving_time { 50 }
    pause_time { 10 }
    distance { 250.0 }
    ascent { 12.0 }
    descent { 4.0 }
    min_elevation { 100.0 }
    max_elevation { 112.0 }
    recorded_elevation { min_elevation.present? }
    average_speed { 5.0 }
    max_speed { 6.0 }
    average_pace { 200 }
    best_pace { 167 }
    start_point { RGeo::Geographic.spherical_factory(srid: 4326).point(6.4074, 45.0710) }
    bounds { [ 45.0710, 6.4074, 45.0728, 6.4092 ] }
    source { "RSpec" }
    import_format { "gpx" }
    points_count { 2 }

    trait :fit do
      import_format { "fit" }
      source { "Allure Test Device" }
    end

    # An indoor recording imported without a GPS position (docs/dev/NO-GPS.md):
    # metrics and sensor readings, no location, no elevation. Its track
    # segments are the `:unpositioned` ones.
    trait :unpositioned do
      start_point { nil }
      bounds { nil }
      min_elevation { nil }
      max_elevation { nil }
      ascent { 0.0 }
      descent { 0.0 }
      recorded_elevation { false }
      import_format { "fit" }
    end

    # A participant's credit row (docs/dev/SHARED-ACTIVITIES.md): the credited metric
    # set only, no location, no file, no device.
    trait :credit do
      origin { "credit" }
      credited_from { association(:workout) }
      credited_by { credited_from.user.actor || association(:local_actor, user: credited_from.user) }
      start_point { nil }
      bounds { nil }
      points_count { nil }
      import_format { nil }
      source { nil }
      min_elevation { nil }
      max_elevation { nil }
    end

    # A workout typed in by hand (PLAN_MANUAL_ENTRY.md §3): the declared
    # figures only, no location, no file, nothing an analysis derives.
    trait :manual do
      origin { "manual" }
      duration { 3600 }
      moving_time { 3600 }
      pause_time { 0 }
      distance { 10_000.0 }
      ascent { 0.0 }
      descent { 0.0 }
      average_speed { 2.7778 }
      average_pace { 360 }
      max_speed { nil }
      best_pace { nil }
      start_point { nil }
      bounds { nil }
      points_count { nil }
      import_format { nil }
      source { nil }
      min_elevation { nil }
      max_elevation { nil }
    end
  end
end
