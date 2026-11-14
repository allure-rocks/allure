# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Workout charts" do
  let(:owner) { create(:user) }
  let(:workout) { create(:workout, user: owner) }

  it "returns cumulative public chart fields without coordinates" do
    create(:track_segment, workout:, position: 0)
    create(
      :track_segment,
      workout:,
      position: 1,
      started_at: workout.started_at + 180,
      distance: 100.0,
      points: [
        { "t" => 0, "d" => 0.0, "lat" => 45.08, "lon" => 6.42 },
        { "t" => 30, "d" => 100.0, "lat" => 45.09, "lon" => 6.43, "ele" => 150.0 }
      ]
    )
    sign_in_as(owner)

    get workout_chart_path(workout)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/json")
    expect(response.headers["Cache-Control"]).to eq("private, no-store")
    expect(response.parsed_body).to eq(
      "points" => [
        { "distance" => 0.0, "elapsed_time" => 0, "elevation" => 100.0 },
        { "distance" => 250.0, "elapsed_time" => 60, "elevation" => 112.0 },
        { "distance" => 250.0, "elapsed_time" => 180, "elevation" => nil },
        { "distance" => 350.0, "elapsed_time" => 210, "elevation" => 150.0 }
      ]
    )
    expect(response.body).not_to include("lat", "lon", "geom", "notes")
  end

  it "returns aligned sensor series only in the owner's v2 response" do
    create(:track_segment, workout:, points: [
      { "t" => 0, "d" => 0.0, "lat" => 45.08, "lon" => 6.42, "ele" => 100.0, "v" => 2.5, "hr" => 140, "cad" => 80, "pw" => 200 },
      { "t" => 60, "d" => 250.0, "lat" => 45.09, "lon" => 6.43, "ele" => 112.0 }
    ])
    sign_in_as(owner)

    get workout_chart_path(workout, version: 2)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(
      "version" => 2,
      "available_series" => %w[elevation speed heart_rate cadence power],
      "points" => [
        { "distance" => 0.0, "elapsed_time" => 0, "elevation" => 100.0, "speed" => 2.5, "heart_rate" => 140, "cadence" => 80, "power" => 200,
          "device_temperature" => nil },
        { "distance" => 250.0, "elapsed_time" => 60, "elevation" => 112.0, "speed" => nil, "heart_rate" => nil, "cadence" => nil, "power" => nil,
          "device_temperature" => nil }
      ]
    )
    expect(response.body).not_to include("lat", "lon", "index", "segment_index")
  end

  it "adds the weather and device temperature channels to the owner's v2 response (PLAN_WEATHER.md §7)" do
    create(:track_segment, workout:, points: [
      { "t" => 0, "d" => 0.0, "lat" => 45.08, "lon" => 6.42, "ele" => 100.0, "temp" => 19 },
      { "t" => 60, "d" => 250.0, "lat" => 45.09, "lon" => 6.43, "ele" => 112.0, "temp" => 21 }
    ])
    create(:workout_weather, workout:)
    sign_in_as(owner)

    get workout_chart_path(workout, version: 2)

    body = response.parsed_body
    expect(body["available_series"]).to include("device_temperature", "temperature", "headwind")
    expect(body["points"].first).to include("device_temperature" => 19, "temperature" => 11.2)
    expect(body["points"].first["headwind"]).to be_a(Numeric)
  end

  it "allows signed-in members when the publication includes analysis" do
    create(:track_segment, workout:)
    profile = create(:publishing_profile, :without_endpoint_masks, user: owner)
    publish_workout!(user: owner, workout:, profile:)
    sign_in_as(create(:user))

    get workout_chart_path(workout)
    expect(response).to have_http_status(:ok)
    legacy_response = response.parsed_body

    get workout_chart_path(workout, version: 2)
    expect(response.parsed_body).to eq(legacy_response)
    expect(response.parsed_body).not_to have_key("version")
    expect(response.body).not_to include("speed", "heart_rate", "cadence", "power")
  end

  it "redirects an anonymous viewer to sign-in" do
    create(:track_segment, workout:)
    profile = create(:publishing_profile, :without_endpoint_masks, user: owner)
    publish_workout!(user: owner, workout:, profile:)

    get workout_chart_path(workout)

    expect(response).to redirect_to(new_session_path)
  end

  it "returns 404 when the publication does not include chart data" do
    create(:track_segment, workout:)
    profile = create(:publishing_profile, :without_endpoint_masks, user: owner, settings: PublishingProfile::DEFAULT_SETTINGS.merge("metrics" => [], "mask_start" => false, "mask_finish" => false))
    publish_workout!(user: owner, workout:, profile:)
    sign_in_as(create(:user))
    get workout_chart_path(workout)
    expect(response).to have_http_status(:not_found)
  end

  it "serves the owner the publication's chart for the reader's view" do
    create(:track_segment, workout:)
    profile = create(:publishing_profile, :without_endpoint_masks, user: owner)
    publication = publish_workout!(user: owner, workout:, profile:)
    sign_in_as(owner)

    get workout_chart_path(workout, as: :publication, version: 2)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq("points" => publication.reload.representation["chart"])
  end

  it "returns 404 for the reader's view chart without an active publication" do
    create(:track_segment, workout:)
    sign_in_as(owner)

    get workout_chart_path(workout, as: :publication)

    expect(response).to have_http_status(:not_found)
  end

  it "always allows the owner regardless of visibility" do
    create(:track_segment, workout:)
    sign_in_as(owner)

    get workout_chart_path(workout)

    expect(response).to have_http_status(:ok)
  end

  it "returns 404 for malformed and unknown identifiers" do
    sign_in_as(create(:user))
    get workout_chart_path(workout_id: "invalid")
    expect(response).to have_http_status(:not_found)

    get workout_chart_path(workout_id: "2222222222222222222222")
    expect(response).to have_http_status(:not_found)
  end
end
