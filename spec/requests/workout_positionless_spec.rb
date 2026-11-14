# frozen_string_literal: true

require "rails_helper"

# An activity imported without any GPS position (PLAN_NO_GPS.md): a trainer
# ride, a treadmill run, a pool swim, a duration-only session. It is measured
# from the device's own records, displayed without any geometry, and cannot be
# published yet.
RSpec.describe "Positionless workouts" do
  let(:owner) { create(:user) }
  let(:sport) { catalog_sport("cycling_virtual") }
  let(:workout) { create(:workout, :unpositioned, user: owner, sport:, title: "Home trainer") }
  let!(:track_segment) { create(:track_segment, :unpositioned, workout:) }

  before do
    workout.original_file.attach(
      io: StringIO.new("<FIT-SUMMARY>"), filename: "indoor.fit", content_type: "application/vnd.ant.fit"
    )
  end

  describe "the owner's page" do
    before { sign_in_as(owner) }

    it "renders without a map and names the missing position" do
      get workout_path(workout)

      expect(response).to have_http_status(:ok)
      # Data attributes and copy are HTML-escaped in the markup.
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("workouts.show.no_position")))
      expect(response.body).not_to include('id="section-map"')
    end

    it "states that the workout has no route to share and offers no publish form" do
      get workout_path(workout)

      expect(response.body).to include(ERB::Util.html_escape(I18n.t("workouts.publication.no_position")))
      expect(response.body).not_to include(I18n.t("workouts.publication.publish"))
      expect(response.body).not_to include(publish_workout_path(workout))
    end

    it "hides the course and route actions that need a geometry" do
      get workout_path(workout)

      expect(response.body).not_to include(new_workout_segment_path(workout))
      expect(response.body).not_to include(new_workout_route_path(workout))
      expect(response.body).not_to include(workout_regenerate_route_image_path(workout))
    end

    it "keeps the original file downloadable" do
      get workout_path(workout)

      expect(response.body).to include(workout_original_file_path(workout))
    end

    it "answers 404 on every geometry endpoint" do
      get workout_track_path(workout)
      expect(response).to have_http_status(:not_found)

      get workout_toponymy_path(workout)
      expect(response).to have_http_status(:not_found)

      post workout_regenerate_route_image_path(workout)
      expect(response).to have_http_status(:not_found)
    end

    it "serves the chart from the recorded sensors" do
      get workout_chart_path(workout, version: 2)

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["points"].length).to eq(2)
      expect(body["available_series"]).to include("heart_rate", "power")
      expect(body["points"].first["heart_rate"]).to eq(120)
      expect(body["points"].first["power"]).to eq(190)
      expect(body["points"].first).not_to have_key("lat")
    end
  end

  describe "the workout list" do
    it "shows the no-position state instead of a route-image skeleton" do
      sign_in_as(owner)

      get workouts_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("workouts.show.no_position"))
      expect(response.body).not_to include(I18n.t("workouts.route_image.pending"))
    end
  end

  describe "publishing" do
    let!(:profile) { create(:publishing_profile, :without_endpoint_masks, user: owner) }

    before { sign_in_as(owner) }

    it "refuses the publication with a no_geometry reason and creates nothing" do
      expect { post publish_workout_path(workout), params: { publishing_profile_id: profile.id } }
        .not_to change(WorkoutPublication, :count)

      expect(response).to redirect_to(workout_path(workout))
      expect(flash[:alert]).to eq(I18n.t("workouts.publish.errors.no_geometry"))
    end

    it "reports the refusal in the publication preview" do
      get publication_preview_workout_path(workout), params: { publishing_profile_id: profile.id },
                                                     headers: { "Accept" => "application/json" }

      # A route/privacy refusal without a candidate is 422 with its reason.
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to include(
        "ready" => false,
        "blocking_error" => I18n.t("workouts.publish.errors.no_geometry")
      )
    end
  end

  describe "the API" do
    it "reports the workout as unpositioned with no track link" do
      get "/api/rest/v1/workouts/#{workout.to_param}", headers: api_headers_for(owner)

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["positioned"]).to be(false)
      expect(body["links"]).not_to have_key("track")
      expect(body["links"]).to have_key("original")
    end
  end
end
