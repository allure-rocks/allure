# frozen_string_literal: true

require "rails_helper"

RSpec.describe "MCP endpoint (PLAN_MCP.md)", type: :request do
  let(:user) { create(:user, time_zone: "Europe/Paris") }
  let(:cycling) { catalog_sport("cycling") }
  let(:running) { catalog_sport("running") }
  let(:geometry_level) { "none" }
  let(:headers) { mcp_headers(user, mcp_geometry: geometry_level) }

  def mcp_headers(user, scopes: %w[read], mcp_geometry: "none")
    _token, secret = ApiToken.issue!(user:, name: "Assistant", scopes:, mcp_geometry:)
    { "Authorization" => "Bearer #{secret}", "Content-Type" => "application/json",
      "Accept" => "application/json, text/event-stream", "MCP-Protocol-Version" => "2025-06-18" }
  end

  def rpc(method, params = nil, headers: self.headers)
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method:, params: }.compact.to_json, headers: headers
    response.parsed_body
  end

  # A tool's answer: [text content parsed as JSON (or the raw text), isError].
  def call_tool(name, arguments = {}, headers: self.headers)
    result = rpc("tools/call", { name:, arguments: }, headers:).fetch("result")
    text = result.dig("content", 0, "text")
    [ (JSON.parse(text) rescue text), result["isError"] ]
  end

  def track(workout, points)
    create(:track_segment, workout:, position: 0, started_at: workout.started_at, points:, distance: points.last["d"])
  end

  describe "the boundary" do
    it "answers 401 without a token and never reads the browser session" do
      post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/list" }.to_json,
                   headers: { "Content-Type" => "application/json" }
      expect(response).to have_http_status(:unauthorized)
      expect(response.headers["WWW-Authenticate"]).to start_with("Bearer")

      sign_in_as(user)
      post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/list" }.to_json,
                   headers: { "Content-Type" => "application/json" }
      expect(response).to have_http_status(:unauthorized)
    end

    it "needs the read scope" do
      rpc("tools/list", headers: mcp_headers(user, scopes: %w[import]))

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["code"]).to eq("insufficient_scope")
    end

    it "refuses a suspended account" do
      headers
      user.update_columns(suspended_at: Time.current)

      rpc("tools/list")

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body["code"]).to eq("account_suspended")
    end

    it "answers 405 to GET and DELETE: no stream, no session" do
      get "/mcp", headers: headers
      expect(response).to have_http_status(:method_not_allowed)
      expect(response.headers["Allow"]).to eq("POST")

      delete "/mcp", headers: headers
      expect(response).to have_http_status(:method_not_allowed)
    end
  end

  describe "the protocol" do
    it "initializes statelessly and advertises tools only" do
      body = rpc("initialize", { protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "spec", version: "1" } })

      expect(response).to have_http_status(:ok)
      expect(response.headers).not_to include("Mcp-Session-Id")
      expect(body.dig("result", "serverInfo")).to include("name" => "allure", "version" => Allure::VERSION)
      expect(body.dig("result", "capabilities")).to eq("tools" => {})
      expect(body.dig("result", "instructions")).to include("list_workouts")
    end

    it "lists the three read-only tools" do
      tools = rpc("tools/list").dig("result", "tools")

      expect(tools.pluck("name")).to contain_exactly("get_workout_context", "list_workouts", "get_workout_series")
      expect(tools.map { it.dig("annotations", "readOnlyHint") }).to all(be(true))
      expect(tools.map { it.dig("inputSchema", "additionalProperties") }).to all(be(false))
    end

    it "refuses unknown arguments as a tool error" do
      answer, error = call_tool("list_workouts", { bogus: 1 })

      expect(error).to be(true)
      expect(answer).to include("bogus")
    end
  end

  describe "list_workouts" do
    it "lists the account's own workouts newest first, never another account's, and pages with a cursor" do
      older = create(:workout, user:, sport: cycling, started_at: Time.zone.parse("2026-08-01 07:00"))
      newer = create(:workout, user:, sport: running, started_at: Time.zone.parse("2026-08-20 07:00"))
      create(:workout, started_at: Time.zone.parse("2026-08-10 07:00"))

      answer, = call_tool("list_workouts", { limit: 1 })
      expect(answer["workouts"].pluck("id")).to eq([ newer.to_param ])
      expect(answer["workouts"].first).to include("sport" => "running", "local_start" => "2026-08-20T09:00:00+02:00")
      expect(answer["account"]).to include("time_zone" => "Europe/Paris")

      answer, = call_tool("list_workouts", { limit: 1, cursor: answer["next_cursor"] })
      expect(answer["workouts"].pluck("id")).to eq([ older.to_param ])
      expect(answer["next_cursor"]).to be_nil
    end

    it "filters by sport and dates, and explains an unknown sport" do
      ride = create(:workout, user:, sport: cycling, started_at: Time.zone.parse("2026-08-10 07:00"))
      create(:workout, user:, sport: running, started_at: Time.zone.parse("2026-08-12 07:00"))
      create(:workout, user:, sport: cycling, started_at: Time.zone.parse("2026-07-01 07:00"))

      answer, = call_tool("list_workouts", { sport: "cycling", from: "2026-08-01", to: "2026-08-31" })
      expect(answer["workouts"].pluck("id")).to eq([ ride.to_param ])

      answer, error = call_tool("list_workouts", { sport: "quidditch" })
      expect(error).to be(true)
      expect(answer).to include("quidditch")
    end
  end

  describe "get_workout_context" do
    let(:workout) do
      create(:workout, user:, sport: running, distance: 1_000, average_speed: 2.5, notes: "Legs heavy",
                       started_at: Time.zone.parse("2026-08-20 07:00"))
    end

    before do
      track(workout, [
        { "t" => 0, "d" => 0.0, "lat" => 45.0710, "lon" => 6.4074, "ele" => 100.0, "hr" => 120 },
        { "t" => 200, "d" => 500.0, "lat" => 45.0755, "lon" => 6.4074, "ele" => 110.0, "hr" => 150 },
        { "t" => 400, "d" => 1000.0, "lat" => 45.0800, "lon" => 6.4074, "ele" => 120.0, "hr" => 165 }
      ])
    end

    it "gathers the owner's figures, analysis and training context" do
      create(:detected_lap, workout:, source: "climb", name: "Col", ascent: 12)
      workout.best_efforts.create!(user:, sport: running, distance_key: "km1", distance_meters: 1_000, duration_seconds: 400,
                                   started_at: workout.started_at)
      earlier = create(:workout, user:, sport: running, started_at: workout.started_at - 3.days, distance: 5_000)
      create(:workout, user:, sport: cycling, started_at: workout.started_at - 2.days, distance: 20_000)

      answer, error = call_tool("get_workout_context", { workout_id: workout.to_param })

      expect(error).to be(false)
      expect(answer["workout"]).to include("id" => workout.to_param, "notes" => "Legs heavy", "average_pace" => 400,
                                           "local_start" => "2026-08-20T09:00:00+02:00")
      expect(answer["workout"]["sport_details"]).to include("slug" => "running", "pace_basis_metres" => 1_000)
      expect(answer.dig("laps", "detected", "climb").first).to include("name" => "Col", "ascent" => 12)
      expect(answer["splits"]["rows"].size).to eq(1)
      expect(answer["best_efforts"].first).to include("distance_key" => "km1", "personal_place" => 1)
      expect(answer["training"]["same_sport"]).to include("workouts" => 1, "distance" => 5_000)
      expect(answer["training"]["all_sports"]).to include("workouts" => 2)
      expect(answer["training"]["recent_same_sport"].pluck("id")).to eq([ earlier.to_param ])
      expect(answer["location_level"]).to eq("none")
    end

    it "carries the athlete's own history on each segment" do
      segment = create(:segment, user:)
      create(:segment_effort, segment:, user:, sport: running, elapsed_time: 300,
                              workout: create(:workout, user:, sport: running, started_at: workout.started_at - 10.days),
                              started_at: workout.started_at - 10.days)
      create(:segment_effort, segment:, workout:, user:, sport: running, elapsed_time: 320, started_at: workout.started_at)

      answer, = call_tool("get_workout_context", { workout_id: workout.to_param })

      history = answer["segment_efforts"].sole["own_history"]
      expect(history).to include("attempts" => 2, "best_time" => 300, "rank_among_own" => 2)
      expect(history["previous_attempt"]).to include("elapsed_time" => 300)
    end

    it "never sends a coordinate unless asked, and only at the token's level" do
      answer, = call_tool("get_workout_context", { workout_id: workout.to_param, include_series: true })

      expect(answer.to_json).not_to include("6.4074", "45.07")
      expect(answer["series"]["columns"]).to eq(%w[distance elapsed_time elevation heart_rate])

      answer, = call_tool("get_workout_context", { workout_id: workout.to_param, include_geometry: true })
      expect(answer["geometry"]).to include("available" => false, "reason" => "token_location_level_none")
      expect(answer.to_json).not_to include("6.4074")
    end

    context "with a token allowing tracks without privacy zones" do
      let(:geometry_level) { "filtered" }

      it "removes every point inside an active zone, the start included" do
        create(:privacy_zone, user:, center: RGeo::Geographic.spherical_factory(srid: 4326).point(6.4074, 45.0710),
                              radius_meters: 100)

        answer, = call_tool("get_workout_context", { workout_id: workout.to_param, include_geometry: true })

        geometry = answer["geometry"]
        expect(geometry).to include("level" => "filtered", "available" => true, "privacy_zones_applied" => 1)
        expect(geometry["coordinates"].flatten(1)).not_to include([ 6.4074, 45.071 ])
        expect(geometry["coordinates"].flatten(1)).to include([ 6.4074, 45.08 ])
      end
    end

    context "with a token allowing complete tracks" do
      let(:geometry_level) { "raw" }

      before do
        create(:privacy_zone, user:, center: RGeo::Geographic.spherical_factory(srid: 4326).point(6.4074, 45.0710),
                              radius_meters: 100)
      end

      it "returns the recorded points, zones included" do
        answer, = call_tool("get_workout_context", { workout_id: workout.to_param, include_geometry: true })

        expect(answer["geometry"]).to include("level" => "raw", "privacy_zones_applied" => 0)
        expect(answer["geometry"]["coordinates"].first.first).to eq([ 6.4074, 45.071 ])
      end

      it "is lowered to the instance's ceiling, even for a token issued before it" do
        headers
        allow(ENV).to receive(:fetch).and_call_original
        allow(ENV).to receive(:fetch).with("MCP_GEOMETRY_MAX", "").and_return("filtered")

        answer, = call_tool("get_workout_context", { workout_id: workout.to_param, include_geometry: true })

        expect(answer["location_level"]).to eq("filtered")
        expect(answer["geometry"]["coordinates"].flatten(1)).not_to include([ 6.4074, 45.071 ])
      end
    end

    it "answers not found for another account's workout, and for nonsense" do
      other = create(:workout, sport: running)

      [ other.to_param, "nope" ].each do |id|
        answer, error = call_tool("get_workout_context", { workout_id: id })

        expect(error).to be(true)
        expect(answer).to start_with("No workout")
      end
    end
  end

  describe "get_workout_series" do
    let(:workout) { create(:workout, user:, sport: running, started_at: Time.zone.parse("2026-08-20 07:00")) }

    before do
      points = (0..100).map do |index|
        { "t" => index * 10, "d" => index * 10.0, "lat" => 45.0 + (index * 0.0001), "lon" => 6.0, "ele" => 100.0 + index,
          "hr" => 120 + (index % 30) }
      end
      track(workout, points)
    end

    it "narrows to a range, thins to max_points, and says which series were not recorded" do
      answer, = call_tool("get_workout_series", { workout_id: workout.to_param, from_distance: 200, to_distance: 600,
                                                  max_points: 5, series: %w[heart_rate power] })

      series = answer["series"]
      expect(series["columns"]).to eq(%w[distance elapsed_time heart_rate])
      expect(series["rows"].size).to eq(5)
      expect(series["rows"].map(&:first)).to all(be_between(200, 600))
      expect(series["points_in_range"]).to eq(41)
      expect(series["missing_series"]).to eq(%w[power])
      expect(answer.to_json).not_to include("45.00")
    end

    it "refuses an inverted range" do
      answer, error = call_tool("get_workout_series", { workout_id: workout.to_param, from_time: 500, to_time: 100 })

      expect(error).to be(true)
      expect(answer).to include("from_time")
    end
  end
end
