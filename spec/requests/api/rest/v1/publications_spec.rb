# frozen_string_literal: true

require "rails_helper"

RSpec.describe "REST API publication (docs/dev/API.md)", type: :request do
  let(:user) { create(:user) }
  let(:workout) { create(:workout, user:, title: "Shareable ride", notes: "Private note") }
  let(:profile) { create(:publishing_profile, :without_endpoint_masks, user:) }
  let(:profile_id) { Allure::ShortId.encode(profile.uuid) }
  let(:headers) { api_headers_for(user, scopes: %w[read publish], "Content-Type" => "application/json") }

  before { create(:track_segment, workout:) }

  def publish(body, target: workout, with: headers)
    post "/api/rest/v1/workouts/#{target.to_param}/publications", params: body.to_json, headers: with
  end

  describe "POST /workouts/:id/publication_previews" do
    it "says what the profile shares, whether it can, and the sentences to show, changing nothing" do
      post "/api/rest/v1/workouts/#{workout.to_param}/publication_previews",
           params: { publishing_profile_id: profile_id }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect_api_contract
      body = response.parsed_body
      expect(body).to include("publishable" => true, "audience" => "public", "refusals" => [])
      expect(body["shared"]).to include("title", "metrics", "route")
      expect(body["not_shared"]).to include("gpx")
      expect(body["copy"]["never"]).to eq(I18n.t("workouts.publish.preview.never", locale: :en))
      expect(body["copy"]["irrevocable"]).to eq(I18n.t("workouts.publication.confirm.body", locale: :en))
      expect(WorkoutPublication.count).to eq(0)
    end

    it "refuses another account's profile" do
      other = create(:publishing_profile, user: create(:user))

      post "/api/rest/v1/workouts/#{workout.to_param}/publication_previews",
           params: { publishing_profile_id: Allure::ShortId.encode(other.uuid) }.to_json, headers: headers

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"]).to contain_exactly(include("field" => "publishing_profile_id",
                                                                        "code" => "unknown_profile"))
    end
  end

  describe "POST /workouts/:id/publications" do
    it "requires the explicit acknowledgement, carrying the irrevocability sentence" do
      publish({ publishing_profile_id: profile_id })

      expect(response).to have_http_status(:unprocessable_content)
      expect_api_contract(request: false)
      expect(response.parsed_body["code"]).to eq("acknowledgement_required")
      expect(response.parsed_body["detail"]).to include(I18n.t("workouts.publication.confirm.body", locale: :en))
      expect(WorkoutPublication.count).to eq(0)

      publish({ publishing_profile_id: profile_id, acknowledge: "true" })
      expect(response.parsed_body["code"]).to eq("acknowledgement_required")
    end

    it "publishes through the web's publisher, live at once with an immediate profile" do
      publish({ publishing_profile_id: profile_id, acknowledge: true })

      expect(response).to have_http_status(:created)
      expect_api_contract
      publication = workout.reload.active_publications.sole
      expect(response.headers["Location"]).to end_with("/api/rest/v1/publications/#{publication.to_param}")
      expect(response.parsed_body).to include("id" => publication.to_param, "status" => "active", "audience" => "public",
                                              "publishing_profile_id" => profile_id)
      expect(FederationOutboxEvent.where(activity_type: "Create", object_uri: publication.object_uri)).to exist
    end

    it "holds the publication for the requested delay, with no federation trace" do
      publish({ publishing_profile_id: profile_id, acknowledge: true, delay: "1_day" })

      expect(response).to have_http_status(:created)
      publication = workout.reload.scheduled_publications.sole
      expect(response.parsed_body["status"]).to eq("scheduled")
      expect(publication.scheduled_for).to be_within(5.seconds).of(1.day.from_now)
      expect(FederationOutboxEvent.where(workout_publication_id: publication.id)).to be_empty
    end

    it "replaces the audience's live publication, as Republish does" do
      publish({ publishing_profile_id: profile_id, acknowledge: true })
      first = workout.reload.active_publications.sole

      publish({ publishing_profile_id: profile_id, acknowledge: true })

      expect(response).to have_http_status(:created)
      replacement = workout.reload.active_publications.sole
      expect(replacement).not_to eq(first)
      expect(first.reload.status).to eq("deleted")
    end

    it "answers publication_refused with the reason when the services refuse" do
      publish({ publishing_profile_id: profile_id, acknowledge: true, delay: "1_day" })

      publish({ publishing_profile_id: profile_id, acknowledge: true })

      expect(response).to have_http_status(:unprocessable_content)
      expect_api_contract
      expect(response.parsed_body).to include("code" => "publication_refused", "reason" => "already_scheduled")
    end

    it "publishes for followers while restricted federation is off" do
      allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(false)
      followers = PublishingProfile.ensure_built_ins_for!(user) && user.publishing_profiles.find_by!(built_in_key: "followers")
      followers.update!(settings: followers.settings.merge("mask_start" => false, "mask_finish" => false))

      publish({ publishing_profile_id: Allure::ShortId.encode(followers.uuid), acknowledge: true })

      expect(response).to have_http_status(:created)
      expect_api_contract
      expect(WorkoutPublication.sole.audience).to eq("followers")
    end

    it "refuses an unknown delay" do
      publish({ publishing_profile_id: profile_id, acknowledge: true, delay: "forever" })

      expect(response.parsed_body["errors"]).to contain_exactly(include("field" => "delay", "code" => "invalid"))
    end

    it "needs the publish scope" do
      publish({ publishing_profile_id: profile_id, acknowledge: true },
              with: api_headers_for(user, scopes: %w[read write], "Content-Type" => "application/json"))

      expect(response.parsed_body["code"]).to eq("insufficient_scope")
      expect(WorkoutPublication.count).to eq(0)
    end

    it "never publishes another account's workout" do
      publish({ publishing_profile_id: profile_id, acknowledge: true }, target: create(:workout))

      expect(response).to have_http_status(:not_found)
    end

    it "publishes once for a retried request with the same Idempotency-Key" do
      keyed = headers.merge("Idempotency-Key" => "publish-1")
      2.times { publish({ publishing_profile_id: profile_id, acknowledge: true }, with: keyed) }

      expect(response).to have_http_status(:created)
      expect(response.headers["Idempotency-Replayed"]).to eq("true")
      expect(WorkoutPublication.count).to eq(1)
    end
  end

  describe "a scheduled publication" do
    let(:scheduled) do
      publish({ publishing_profile_id: profile_id, acknowledge: true, delay: "1_week" })
      workout.reload.scheduled_publications.sole
    end

    it "is listed with the workout's publications" do
      scheduled

      get "/api/rest/v1/workouts/#{workout.to_param}/publications", headers: headers

      expect(response.parsed_body["data"].pluck("id", "status")).to eq([ [ scheduled.to_param, "scheduled" ] ])
      expect_api_contract
    end

    it "is rescheduled to another delay from now" do
      patch "/api/rest/v1/publications/#{scheduled.to_param}", params: { delay: "1_day" }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect_api_contract
      expect(scheduled.reload.scheduled_for).to be_within(5.seconds).of(1.day.from_now)
    end

    it "goes live on activation, once" do
      post "/api/rest/v1/publications/#{scheduled.to_param}/activation", headers: headers

      expect(response).to have_http_status(:ok)
      expect_api_contract
      expect(scheduled.reload).to be_active

      post "/api/rest/v1/publications/#{scheduled.to_param}/activation", headers: headers
      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body["code"]).to eq("not_scheduled")
    end

    it "is cancelled without a federation trace" do
      delete "/api/rest/v1/publications/#{scheduled.to_param}", headers: headers

      expect(response).to have_http_status(:no_content)
      expect(scheduled.reload.status).to eq("deleted")
      expect(FederationOutboxEvent.where(workout_publication_id: scheduled.id)).to be_empty
    end
  end

  it "deletes a live publication and sends the deletion" do
    publish({ publishing_profile_id: profile_id, acknowledge: true })
    publication = workout.reload.active_publications.sole

    delete "/api/rest/v1/publications/#{publication.to_param}", headers: headers

    expect(response).to have_http_status(:no_content)
    expect_api_contract
    expect(publication.reload.status).to eq("deleted")
    expect(FederationOutboxEvent.where(activity_type: "Delete", object_uri: publication.object_uri)).to exist

    delete "/api/rest/v1/publications/#{publication.to_param}", headers: headers
    expect(response).to have_http_status(:not_found)
  end

  it "never reaches another account's publication" do
    other_workout = create(:workout)
    create(:track_segment, workout: other_workout)
    other_profile = create(:publishing_profile, :without_endpoint_masks, user: other_workout.user)
    other = Workouts::Publisher.new(user: other_workout.user, workout: other_workout, profile: other_profile).call!

    delete "/api/rest/v1/publications/#{other.to_param}", headers: headers

    expect(response).to have_http_status(:not_found)
    expect(other.reload).to be_active
  end
end
