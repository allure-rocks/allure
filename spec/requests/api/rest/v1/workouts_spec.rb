# frozen_string_literal: true

require "rails_helper"

RSpec.describe "REST API workouts (docs/dev/API.md)", type: :request do
  let(:user) { create(:user) }
  let(:headers) { api_headers_for(user) }
  let(:cycling) { catalog_sport("cycling") }
  let(:running) { catalog_sport("running") }

  def workout_at(time, **attributes)
    create(:workout, user:, sport: cycling, started_at: Time.zone.parse(time), **attributes)
  end

  describe "GET /workouts" do
    it "lists the account's workouts newest first, never another account's" do
      older = workout_at("2026-08-01 07:00")
      newer = workout_at("2026-08-20 07:00")
      create(:workout, started_at: Time.zone.parse("2026-08-10 07:00"))

      get "/api/rest/v1/workouts", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["data"].pluck("id")).to eq([ newer.to_param, older.to_param ])
      expect(response.parsed_body["next_cursor"]).to be_nil
      expect(response.parsed_body["data"].first).not_to include("notes", "data_anomalies", "description")
      expect_api_contract
    end

    it "pages through every workout with the cursor, in the requested order" do
      workouts = 5.times.map { |index| workout_at("2026-08-0#{index + 1} 07:00", distance: 1_000 * (5 - index)) }

      seen = []
      cursor = nil
      loop do
        get "/api/rest/v1/workouts", params: { limit: 2, sort: "distance", cursor: }.compact, headers: headers
        expect_api_contract
        seen.concat(response.parsed_body["data"].pluck("id"))
        cursor = response.parsed_body["next_cursor"]
        break if cursor.nil?
      end

      expect(seen).to eq(workouts.sort_by(&:distance).map(&:to_param))
    end

    it "refuses a cursor issued for another ordering, and a malformed one" do
      3.times { |index| workout_at("2026-08-0#{index + 1} 07:00") }
      get "/api/rest/v1/workouts", params: { limit: 1 }, headers: headers
      cursor = response.parsed_body["next_cursor"]

      get "/api/rest/v1/workouts", params: { limit: 1, sort: "-distance", cursor: }, headers: headers
      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["code"]).to eq("invalid_cursor")

      get "/api/rest/v1/workouts", params: { cursor: "garbage" }, headers: headers
      expect(response.parsed_body["code"]).to eq("invalid_cursor")
    end

    it "filters by sport, dates, commute and equipment" do
      ride = workout_at("2026-08-10 07:00", commute: true)
      run = workout_at("2026-08-12 07:00", sport: running)
      workout_at("2026-07-01 07:00")
      bike = create(:equipment, user:)
      ride.equipments << bike

      get "/api/rest/v1/workouts", params: { sport: "running" }, headers: headers
      expect(response.parsed_body["data"].pluck("id")).to eq([ run.to_param ])

      get "/api/rest/v1/workouts", params: { from: "2026-08-01", to: "2026-08-11" }, headers: headers
      expect(response.parsed_body["data"].pluck("id")).to eq([ ride.to_param ])
      expect_api_contract

      get "/api/rest/v1/workouts", params: { commute: "true" }, headers: headers
      expect(response.parsed_body["data"].pluck("id")).to eq([ ride.to_param ])

      get "/api/rest/v1/workouts", params: { equipment: bike.to_param }, headers: headers
      expect(response.parsed_body["data"].pluck("id")).to eq([ ride.to_param ])
    end

    it "answers 400 for an unknown sport, sort or limit" do
      [ { sport: "quidditch" }, { sort: "random" }, { limit: 0 }, { limit: 101 }, { from: "yesterday" },
        { commute: "maybe" } ].each do |params|
        get "/api/rest/v1/workouts", params:, headers: headers

        expect(response).to have_http_status(:bad_request), params.inspect
        expect(response.parsed_body["code"]).to eq("invalid_parameter")
      end
    end

    it "does not refer to another account's equipment" do
      other = create(:equipment)

      get "/api/rest/v1/workouts", params: { equipment: other.to_param }, headers: headers

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "GET /workouts/:id weather (PLAN_WEATHER.md §8)" do
    it "carries the status, the SI summary and the hourly series" do
      workout = workout_at("2026-08-10 07:00")
      create(:workout_weather, workout:)

      get "/api/rest/v1/workouts/#{workout.to_param}", headers: headers

      weather = response.parsed_body["weather"]
      expect(weather["status"]).to eq("ready")
      expect(weather["summary"]).to include("condition" => "partly_cloudy", "temperature_max" => 15.8,
                                            "is_day" => true)
      expect(weather["summary"]["wind_exposure"]).to include("head" => 0.42)
      expect(weather["hours"].length).to eq(2)
      expect(weather["hours"].first).to include("day" => true)
      expect(weather["hours"].first.keys).not_to include("lat", "lon", "latitude", "longitude")
      expect_api_contract
    end

    it "is null when no weather was asked" do
      get "/api/rest/v1/workouts/#{workout_at("2026-08-10 07:00").to_param}", headers: headers

      expect(response.parsed_body["weather"]).to be_nil
      expect_api_contract
    end
  end

  describe "GET /workouts/:id" do
    it "returns the owner's detail in SI units" do
      workout = workout_at("2026-08-23 06:00", description: "Col", notes: "Legs heavy", duration: 3_600,
                                               moving_time: 3_000, pause_time: 600, distance: 25_000.5)
      workout.update_columns(places: [ { "kind" => "town", "name" => "Annecy" } ],
                             data_anomalies: { "findings" => [ { "kind" => "gps_jump", "tier" => "major",
                                                                 "start_distance" => 10.0, "end_distance" => 20.0 } ] })

      get "/api/rest/v1/workouts/#{workout.to_param}", headers: headers

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body).to include("id" => workout.to_param, "sport" => "cycling", "distance" => 25_000.5,
                              "elapsed_time" => 3_600, "notes" => "Legs heavy", "places" => [ "Annecy" ],
                              "started_at" => "2026-08-23T06:00:00Z", "ended_at" => "2026-08-23T07:00:00Z")
      expect(body["data_anomalies"].first).to include("kind" => "gps_jump", "tier" => "major")
      expect(body["links"]["track"]).to end_with("/api/rest/v1/workouts/#{workout.to_param}/track")
      expect(body.to_s).not_to include(workout.id.to_s + ",")
      expect_api_contract
    end

    it "answers 404 for another account's workout and for a malformed identifier" do
      other = create(:workout)

      get "/api/rest/v1/workouts/#{other.to_param}", headers: headers
      expect(response).to have_http_status(:not_found)
      expect_api_contract

      get "/api/rest/v1/workouts/not-an-id", headers: headers
      expect(response).to have_http_status(:not_found)
    end

    it "answers 304 while the workout is unchanged" do
      workout = workout_at("2026-08-23 06:00")

      get "/api/rest/v1/workouts/#{workout.to_param}", headers: headers
      etag = response.headers["ETag"]
      get "/api/rest/v1/workouts/#{workout.to_param}", headers: headers.merge("If-None-Match" => etag)
      expect(response).to have_http_status(:not_modified)

      workout.update!(title: "Renamed")
      get "/api/rest/v1/workouts/#{workout.to_param}", headers: headers.merge("If-None-Match" => etag)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /workouts/:id/track" do
    it "returns one GeoJSON feature per recording segment, in [longitude, latitude] order" do
      workout = workout_at("2026-08-23 06:00")
      create(:track_segment, workout:, position: 0)
      create(:track_segment, workout:, position: 1, points: [
        { "t" => 0, "d" => 0.0, "lat" => 45.1, "lon" => 6.5, "ele" => 120.0, "hr" => 140 },
        { "t" => 30, "d" => 100.0, "lat" => 45.2, "lon" => 6.6, "ele" => 125.0, "hr" => 150 }
      ])

      get "/api/rest/v1/workouts/#{workout.to_param}/track", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/geo+json")
      features = JSON.parse(response.body)["features"]
      expect(features.size).to eq(2)
      expect(features.first["geometry"]["coordinates"].first).to eq([ 6.4074, 45.071 ])
      expect(features.last["properties"]).to include("segment_index" => 1, "heart_rates" => [ 140, 150 ],
                                                     "distances" => [ 250.0, 350.0 ])
      expect(features.first["properties"]).not_to have_key("heart_rates")
      expect_api_contract
    end

    it "is owner-only" do
      other = create(:workout)
      create(:track_segment, workout: other)

      get "/api/rest/v1/workouts/#{other.to_param}/track", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /workouts/:id/original" do
    it "downloads the original file" do
      workout = workout_at("2026-08-23 06:00")
      workout.original_file.attach(io: StringIO.new("<gpx/>"), filename: "ride.gpx", content_type: "application/gpx+xml")

      get "/api/rest/v1/workouts/#{workout.to_param}/original", headers: headers

      expect(response).to have_http_status(:ok)
      expect(response.body).to eq("<gpx/>")
      expect(response.headers["Content-Disposition"]).to include("attachment", "ride.gpx")
      expect_api_contract
    end

    it "answers 404 when there is no original file" do
      workout = workout_at("2026-08-23 06:00")

      get "/api/rest/v1/workouts/#{workout.to_param}/original", headers: headers

      expect(response).to have_http_status(:not_found)
    end
  end
end
