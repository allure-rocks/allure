# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Route suggestions" do
  let(:user) { create(:user) }
  let(:sport) { create(:sport) }
  let(:workout) { route_suggestion_recording(user:, sport:, started_at: 1.day.ago) }
  let(:reference) { route_suggestion_recording(user:, sport:, started_at: 2.days.ago) }
  let(:third) { route_suggestion_recording(user:, sport:, started_at: 3.days.ago) }

  def suggestion_for(members: [ workout, reference, third ], **attributes)
    suggestion = create(:route_suggestion, user:, sport:, reference_workout: reference, **attributes)
    members.each { |member| create(:route_suggestion_workout, route_suggestion: suggestion, workout: member) }
    suggestion
  end

  describe "the banner" do
    it "shows the suggestion on every member to the owner" do
      suggestion_for
      sign_in_as(user)

      get workout_path(workout)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("route_suggestions.banner.title"))
      expect(response.body).to include(I18n.t("route_suggestions.banner.save"))
      expect(response.body).to include(I18n.t("route_suggestions.banner.dismiss"))
    end

    it "renders nothing once the suggestion is dismissed" do
      suggestion_for(status: "dismissed")
      sign_in_as(user)

      get workout_path(workout)

      expect(response.body).not_to include(I18n.t("route_suggestions.banner.title"))
    end

    it "renders nothing for a recording outside the suggestion" do
      suggestion_for
      other = route_suggestion_recording(user:, sport:, started_at: 4.days.ago)
      sign_in_as(user)

      get workout_path(other)

      expect(response.body).not_to include(I18n.t("route_suggestions.banner.title"))
    end

    it "hides the banner once the reference carries a route effort" do
      suggestion_for
      route = Segments::Creator.new(user:, workout: reference, kind: "route", name: "Commute").call
      create(:segment_effort, workout: reference, segment: route)
      sign_in_as(user)

      get workout_path(workout)

      expect(response.body).not_to include(I18n.t("route_suggestions.banner.title"))
    end

    it "never shows the banner in the owner's reader preview" do
      suggestion_for
      profile = create(:publishing_profile, user:)
      create(:workout_publication, workout:, publishing_profile: profile)
      sign_in_as(user)

      get workout_path(workout, as: :publication)

      expect(response.body).not_to include(I18n.t("route_suggestions.banner.title"))
    end
  end

  describe "dismissing" do
    it "closes the suggestion for good" do
      suggestion = suggestion_for
      sign_in_as(user)

      patch dismiss_route_suggestion_path(suggestion)

      expect(response).to redirect_to(workouts_path)
      expect(suggestion.reload).to be_dismissed
      expect(flash[:notice]).to eq(I18n.t("route_suggestions.notices.dismissed"))
    end

    it "never touches another account's suggestion" do
      suggestion = suggestion_for
      sign_in_as(create(:user))

      patch dismiss_route_suggestion_path(suggestion)

      expect(response).to have_http_status(:not_found)
      expect(suggestion.reload).to be_pending
    end
  end

  describe "the prefilled route form" do
    it "proposes a name from the places and states the attached activities" do
      suggestion = suggestion_for
      reference.update_columns(places: [ { "name" => "Meylan" }, { "name" => "Grenoble" } ])
      sign_in_as(user)

      get new_workout_route_path(reference, route_suggestion: suggestion.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Meylan → Grenoble")
      expect(response.body).to include("les 3 activités de ce parcours y seront rattachées")
      expect(response.parsed_body.at_css("input#route_match_tolerance_meters")["value"]).to eq("100")
    end
  end

  describe "accepting" do
    it "accepts the suggestion when the route is saved from one of its recordings" do
      suggestion = suggestion_for
      sign_in_as(user)

      expect do
        post workout_routes_path(workout, route_suggestion: suggestion.id), params: {
          route: { name: "Commute", match_tolerance_meters: 25 }
        }
      end.to change(Segment, :count).by(1)

      route = Segment.order(:id).last
      expect(response).to redirect_to(segment_path(route))
      expect(suggestion.reload).to be_accepted
      expect(suggestion.segment).to eq(route)
    end

    it "leaves the suggestion pending when the route comes from another recording" do
      suggestion = suggestion_for
      other = route_suggestion_recording(user:, sport:, started_at: 4.days.ago)
      sign_in_as(user)

      post workout_routes_path(other), params: {
        route: { name: "Another route", match_tolerance_meters: 25 }
      }

      expect(suggestion.reload).to be_pending
    end
  end
end
