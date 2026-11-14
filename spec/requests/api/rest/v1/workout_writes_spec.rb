# frozen_string_literal: true

require "rails_helper"

RSpec.describe "REST API workout writes (PLAN_API.md §6.3)", type: :request do
  let(:user) { create(:user) }
  let(:headers) { api_headers_for(user, scopes: %w[write], "Content-Type" => "application/json") }
  let(:cycling) { catalog_sport("cycling") }
  let(:workout) { create(:workout, user:, sport: cycling, title: "Morning ride", notes: "Old") }

  def patch_workout(body, target: workout, with: headers)
    patch "/api/rest/v1/workouts/#{target.to_param}", params: body.to_json, headers: with
  end

  describe "PATCH /workouts/:id" do
    it "changes only the fields sent and answers the updated workout" do
      patch_workout({ title: "Col du Galibier", notes: nil, commute: true })

      expect(response).to have_http_status(:ok)
      expect_api_contract
      expect(response.parsed_body).to include("title" => "Col du Galibier", "notes" => nil, "commute" => true)
      expect(workout.reload).to have_attributes(title: "Col du Galibier", notes: nil, commute: true, sport: cycling)
    end

    it "replaces the equipment with the account's own pieces and keeps the totals in step" do
      bike = create(:equipment, user:)
      shoes = create(:equipment, user:)
      Equipments::Totals.sync(workout, [ shoes.id ])

      patch_workout({ equipment_ids: [ bike.to_param ] })

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["equipment_ids"]).to eq([ bike.to_param ])
      expect(bike.reload.total_workouts).to eq(1)
      expect(shoes.reload.total_workouts).to eq(0)
    end

    it "refuses another account's equipment, unknown fields and wrong types, changing nothing" do
      other = create(:equipment)

      patch_workout({ equipment_ids: [ other.to_param ], commute: "yes", sport: "quidditch", distance: 1, title: "Kept?" })

      expect(response).to have_http_status(:unprocessable_content)
      expect_api_contract(request: false)
      expect(response.parsed_body["errors"].pluck("field", "code")).to contain_exactly(
        %w[distance not_editable], %w[commute invalid_type], %w[sport unknown_sport], %w[equipment_ids unknown_equipment]
      )
      expect(workout.reload.title).to eq("Morning ride")
    end

    it "reports a model validation as a field error" do
      patch_workout({ notes: "x" * 501 })

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"]).to contain_exactly(include("field" => "notes", "code" => "too_long"))
    end

    it "changes the sport through the web's sport change" do
      running = catalog_sport("running")
      change = instance_double(Workouts::SportChange, call!: workout)
      allow(Workouts::SportChange).to receive(:new).with(workout: an_instance_of(Workout), sport: running).and_return(change)

      patch_workout({ sport: "running" })

      expect(response).to have_http_status(:ok)
      expect(change).to have_received(:call!)
    end

    it "answers sport_change_failed when the workout cannot be analysed again" do
      catalog_sport("running")

      patch_workout({ sport: "running" })

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["code"]).to eq("sport_change_failed")
      expect(workout.reload.sport).to eq(cycling)
    end

    it "refuses a body that is not JSON" do
      patch "/api/rest/v1/workouts/#{workout.to_param}", params: "{nope", headers: headers

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["code"]).to eq("invalid_parameter")
    end

    it "needs the write scope, and never reaches another account's workout" do
      patch_workout({ title: "X" }, with: api_headers_for(user, scopes: %w[read], "Content-Type" => "application/json"))
      expect(response.parsed_body["code"]).to eq("insufficient_scope")

      patch_workout({ title: "X" }, target: create(:workout))
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /workouts (PLAN_MANUAL_ENTRY.md §8)" do
    let(:body) do
      { sport: "running", started_at: "2026-10-17T07:30:00+02:00", elapsed_time: 2730, distance: 8500,
        ascent: 120, average_heart_rate: 145, max_heart_rate: 170, title: "Footing sans montre" }
    end

    def post_workout(payload, with: headers)
      post "/api/rest/v1/workouts", params: payload.to_json, headers: with
    end

    it "creates a manual entry and answers it with its location" do
      catalog_sport("running")

      post_workout(body)

      expect(response).to have_http_status(:created)
      expect_api_contract
      workout = user.workouts.manual_entries.sole
      expect(response.headers["Location"]).to end_with("/api/rest/v1/workouts/#{workout.to_param}")
      expect(response.parsed_body).to include(
        "origin" => "manual", "positioned" => false, "elapsed_time" => 2730, "moving_time" => 2730,
        "distance" => 8500, "import_format" => nil, "title" => "Footing sans montre"
      )
      expect(response.parsed_body["links"].keys).to contain_exactly("self", "web")
      expect(workout.started_at).to eq(Time.utc(2026, 10, 17, 5, 30))
    end

    it "requires the sport, the start and the elapsed time, and checks every type" do
      post_workout({ distance: "far", started_at: "2026-10-17T07:30", average_heart_rate: 140.5, colour: "red" })

      expect(response).to have_http_status(:unprocessable_content)
      expect_api_contract(request: false)
      expect(response.parsed_body["errors"].pluck("field", "code")).to contain_exactly(
        %w[sport required], %w[elapsed_time required], %w[started_at invalid_type], %w[distance invalid_type],
        %w[average_heart_rate invalid_type], %w[colour unknown]
      )
      expect(user.workouts).to be_empty
    end

    it "reports the model's refusals under the representation's names" do
      catalog_sport("running")

      post_workout(body.merge(elapsed_time: 0, max_heart_rate: 100))

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"].pluck("field", "code")).to include(
        %w[elapsed_time implausible], %w[max_heart_rate below_average]
      )
    end

    it "replays an idempotent creation" do
      catalog_sport("running")
      keyed = headers.merge("Idempotency-Key" => "manual-1")

      2.times { post_workout(body, with: keyed) }

      expect(response).to have_http_status(:created)
      expect(response.headers["Idempotency-Replayed"]).to eq("true")
      expect(user.workouts.count).to eq(1)
    end

    it "needs the write scope" do
      post_workout(body, with: api_headers_for(user, scopes: %w[read], "Content-Type" => "application/json"))

      expect(response.parsed_body["code"]).to eq("insufficient_scope")
    end
  end

  describe "PATCH /workouts/:id on a manual entry" do
    let(:entry) { create(:workout, :manual, user:, sport: catalog_sport("running"), duration: 3000, moving_time: 3000) }

    it "takes its figures and clears an optional one" do
      entry.update!(calories: 500)

      patch_workout({ elapsed_time: 3600, distance: 11_000, calories: nil }, target: entry)

      expect(response).to have_http_status(:ok)
      expect_api_contract
      expect(entry.reload).to have_attributes(duration: 3600, moving_time: 3600, distance: 11_000, calories: nil)
    end

    it "changes its sport without any file" do
      patch_workout({ sport: "trail" }, target: entry.tap { catalog_sport("trail") })

      expect(response).to have_http_status(:ok)
      expect(entry.reload.sport.slug).to eq("trail")
    end
  end

  describe "DELETE /workouts/:id" do
    it "deletes through the web's deletion cascade and answers 204" do
      deletion = instance_double(Workouts::WorkoutDeletion, call!: true)
      allow(Workouts::WorkoutDeletion).to receive(:new).with(user:, workout:).and_return(deletion)

      delete "/api/rest/v1/workouts/#{workout.to_param}", headers: headers

      expect(response).to have_http_status(:no_content)
      expect(deletion).to have_received(:call!)
      expect_api_contract
    end

    it "removes the workout" do
      delete "/api/rest/v1/workouts/#{workout.to_param}", headers: headers

      expect(Workout.exists?(workout.id)).to be(false)
    end

    it "answers 404 for another account's workout" do
      other = create(:workout)

      delete "/api/rest/v1/workouts/#{other.to_param}", headers: headers

      expect(response).to have_http_status(:not_found)
      expect(Workout.exists?(other.id)).to be(true)
    end
  end
end
