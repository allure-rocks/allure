# frozen_string_literal: true

require "rails_helper"

RSpec.describe "REST API workout analysis and records (PLAN_API.md §6.2)", type: :request do
  let(:user) { create(:user) }
  let(:headers) { api_headers_for(user) }
  let(:cycling) { catalog_sport("cycling") }
  let(:workout) { create(:workout, user:, sport: cycling) }

  it "lists recorded laps, then detected ones, each with its source" do
    create(:lap, workout:, number: 1)
    create(:detected_lap, workout:, source: "climb", name: "Col", ascent: 12)

    get "/api/rest/v1/workouts/#{workout.to_param}/laps", headers: headers

    expect(response).to have_http_status(:ok)
    expect_api_contract
    expect(response.parsed_body["data"].pluck("source")).to eq(%w[recorded climb])
    expect(response.parsed_body["data"].last).to include("name" => "Col", "ascent" => 12)
  end

  it "splits the track over the requested distance" do
    create(:track_segment, workout:, points: [
      { "t" => 0, "d" => 0.0, "lat" => 45.0, "lon" => 6.0, "ele" => 100.0, "pw" => 200 },
      { "t" => 100, "d" => 500.0, "lat" => 45.004, "lon" => 6.0, "ele" => 110.0, "pw" => 220 },
      { "t" => 200, "d" => 1000.0, "lat" => 45.009, "lon" => 6.0, "ele" => 120.0, "pw" => 240 }
    ])

    get "/api/rest/v1/workouts/#{workout.to_param}/splits", params: { distance: 500 }, headers: headers

    expect(response).to have_http_status(:ok)
    expect_api_contract
    expect(response.parsed_body["distance"]).to eq(500)
    expect(response.parsed_body["data"].size).to eq(2)
    expect(response.parsed_body["data"].map { |row| row["average_power"] }).to eq([ 210, 230 ])

    get "/api/rest/v1/workouts/#{workout.to_param}/splits", params: { distance: 10 }, headers: headers
    expect(response).to have_http_status(:bad_request)
  end

  it "lists best efforts with their personal place" do
    workout.best_efforts.create!(user:, sport: cycling, distance_key: "10k", distance_meters: 10_000, duration_seconds: 900,
                                 started_at: workout.started_at)

    get "/api/rest/v1/workouts/#{workout.to_param}/best_efforts", headers: headers

    expect(response).to have_http_status(:ok)
    expect_api_contract
    expect(response.parsed_body["data"].first).to include("distance_key" => "10k", "elapsed_time" => 900, "personal_place" => 1)
  end

  it "lists segment efforts with the segment named" do
    effort = create(:segment_effort, workout:, user:, sport: cycling)

    get "/api/rest/v1/workouts/#{workout.to_param}/segment_efforts", headers: headers

    expect(response).to have_http_status(:ok)
    expect_api_contract
    expect(response.parsed_body["data"].first).to include("id" => effort.to_param)
    expect(response.parsed_body["data"].first["segment"]).to include("id" => effort.segment.to_param)
  end

  it "lists the account's records only" do
    workout.update!(distance: 42_000)
    other = create(:workout, sport: cycling, distance: 99_000)
    [ user, other.user ].each { Records::RecomputeService.new(user: it, sport: cycling).call }

    get "/api/rest/v1/records", headers: headers

    expect(response).to have_http_status(:ok)
    expect_api_contract
    records = response.parsed_body["records"]
    expect(records).to include(include("sport" => "cycling", "type" => "FD", "value" => 42_000, "workout_id" => workout.to_param))
    expect(records.pluck("workout_id")).not_to include(other.to_param)
  end

  it "keeps the analysis owner-only" do
    other = create(:workout)

    %w[laps splits best_efforts segment_efforts].each do |name|
      get "/api/rest/v1/workouts/#{other.to_param}/#{name}", headers: headers
      expect(response).to have_http_status(:not_found), name
    end
  end
end
