# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Workout toponymies" do
  let(:owner) { create(:user) }
  let(:workout) { create(:workout, user: owner) }

  it "returns the owner's route context and markers without coordinates" do
    create(:workout_toponymy, workout:)
    sign_in_as(owner)

    get workout_toponymy_path(workout)

    expect(response).to have_http_status(:ok)
    expect(response.headers["Cache-Control"]).to eq("private, no-store")
    expect(response.parsed_body).to eq(
      "status" => "ready",
      "start" => { "name" => "Valmorin", "kind" => "village" },
      "finish" => { "name" => "Rochelune", "kind" => "city" },
      "loop" => false,
      "markers" => [
        { "distance" => 20_000.0, "elevation" => 250.0, "name" => "Cimefroide", "kind" => "town", "rank" => 1 }
      ]
    )
    expect(response.body).not_to include("latitude", "longitude", "samples", "provider")
  end

  it "returns landmark markers without exposing source metadata" do
    create(
      :workout_toponymy,
      workout:,
      markers: [
        { "distance" => 12_000.0, "elevation" => 180.0, "name" => "Citadel of Rochelune", "kind" => "landmark", "rank" => 1,
          "osm_id" => 121_629_346 }
      ]
    )
    sign_in_as(owner)

    get workout_toponymy_path(workout)

    expect(response.parsed_body["markers"]).to eq([
      { "distance" => 12_000.0, "elevation" => 180.0, "name" => "Citadel of Rochelune", "kind" => "landmark", "rank" => 1 }
    ])
    expect(response.body).not_to include("osm_id")
  end

  it "returns sanitized markers without source track data or sample metadata" do
    create(
      :workout_toponymy,
      workout:,
      samples: [
        {
          "distance" => 22_900.1, "elevation" => 242.0, "role" => "climb_summit",
          "climb_gain" => 144.1, "climb_prominence" => 63.6,
          "latitude" => 50.0, "longitude" => 5.0, "result" => { "secret" => true }
        },
        { "distance" => 1_000.0, "elevation" => 200.0, "role" => "route" }
      ]
    )
    sign_in_as(owner)

    get workout_toponymy_path(workout)

    expect(response.parsed_body["markers"]).to eq([
      { "distance" => 20_000.0, "elevation" => 250.0, "name" => "Cimefroide", "kind" => "town", "rank" => 1 }
    ])
    expect(response.parsed_body).not_to have_key("climb_summits")
    expect(response.body).not_to include("latitude", "longitude", "secret", "climb_gain")
  end

  it "answers unavailable for a missing toponymy without scheduling geocoding" do
    sign_in_as(owner)

    expect do
      get workout_toponymy_path(workout)
    end.not_to have_enqueued_job(Workouts::EnrichToponymyJob)

    expect(response.parsed_body).to eq("status" => "unavailable")
    expect(workout.reload.toponymy).to be_nil
  end

  it "reads an outdated, stuck, or failed toponymy as it is" do
    toponymy = create(:workout_toponymy, workout:, algorithm_version: Workouts::ToponymyEnricher::ALGORITHM_VERSION - 1)
    sign_in_as(owner)

    expect do
      get workout_toponymy_path(workout)
      toponymy.update_columns(status: "pending", updated_at: 1.day.ago)
      get workout_toponymy_path(workout)
      expect(response.parsed_body).to eq("status" => "pending")
      toponymy.update_columns(status: "failed", updated_at: 1.day.ago)
      get workout_toponymy_path(workout)
    end.not_to have_enqueued_job(Workouts::EnrichToponymyJob)

    expect(response.parsed_body).to eq("status" => "failed")
    expect(toponymy.reload.updated_at).to be < 1.hour.ago
  end

  it "returns only status for failed enrichment" do
    create(:workout_toponymy, workout:, status: "failed", last_error: "secret internal failure")
    sign_in_as(owner)

    get workout_toponymy_path(workout)

    expect(response.parsed_body).to eq("status" => "failed")
    expect(response.body).not_to include("secret")
  end

  it "marks a route as a loop when its endpoints are within the display closure radius" do
    points = [
      { "t" => 0, "d" => 0.0, "lat" => 45.0710, "lon" => 6.4074, "ele" => 100.0 },
      { "t" => 60, "d" => 1_000.0, "lat" => 45.0710, "lon" => 6.4090, "ele" => 100.0 }
    ]
    factory = RGeo::Geographic.spherical_factory(srid: 4326)
    create(
      :track_segment,
      workout:,
      distance: 1_000.0,
      points:,
      points_count: points.length,
      geom: factory.line_string(points.map { |point| factory.point(point.fetch("lon"), point.fetch("lat")) })
    )
    create(
      :workout_toponymy,
      workout:,
      start_place: { "name" => "Habitat groupé Pa-d'zo l'Haye", "kind" => "neighbourhood" },
      finish_place: { "name" => "Les Plains de Chansin", "kind" => "locality" }
    )
    sign_in_as(owner)

    get workout_toponymy_path(workout)

    expect(response.parsed_body["loop"]).to be(true)
  end

  it "does not mark a route as a loop when its endpoints exceed the display closure radius" do
    points = [
      { "t" => 0, "d" => 0.0, "lat" => 45.0710, "lon" => 6.4074, "ele" => 100.0 },
      { "t" => 60, "d" => 1_000.0, "lat" => 45.0710, "lon" => 6.4110, "ele" => 100.0 }
    ]
    factory = RGeo::Geographic.spherical_factory(srid: 4326)
    create(
      :track_segment,
      workout:,
      distance: 1_000.0,
      points:,
      points_count: points.length,
      geom: factory.line_string(points.map { |point| factory.point(point.fetch("lon"), point.fetch("lat")) })
    )
    create(
      :workout_toponymy,
      workout:,
      start_place: { "name" => "Rochelune", "kind" => "city" },
      finish_place: { "name" => "Rochelune", "kind" => "city" }
    )
    sign_in_as(owner)

    get workout_toponymy_path(workout)

    expect(response.parsed_body["loop"]).to be(false)
  end

  it "returns 404 to anonymous users and other accounts" do
    create(:workout_toponymy, workout:)

    get workout_toponymy_path(workout)
    expect(response).to redirect_to(new_session_path)

    sign_in_as(create(:user))
    get workout_toponymy_path(workout)
    expect(response).to have_http_status(:not_found)
  end

  it "answers unavailable for a virtual sport, leaving a legacy toponymy to the sweep" do
    workout = create(:workout, user: owner, sport: catalog_sport("rowing_virtual"))
    create(:workout_toponymy, workout:)
    sign_in_as(owner)

    expect do
      get workout_toponymy_path(workout)
    end.not_to have_enqueued_job(Workouts::EnrichToponymyJob)

    expect(response.parsed_body).to eq("status" => "unavailable")
    expect(workout.reload.toponymy).to be_present
  end
end
