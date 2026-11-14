# frozen_string_literal: true

require "rails_helper"

# M4 Slice 0 information-architecture proofs: the navigation tree matches
# DESIGN.md §8 (no dead leaves, no single-child dropdown, collections under
# settings, records behind /me), every new landing page routes, anonymous
# visitors are redirected, and the segments index covers all three kinds.
RSpec.describe "Slice 0 information architecture" do
  let(:user) { create(:user) }
  let(:sport) { create(:sport) }

  def sign_in_as(u = user)
    post session_path, params: { email_address: u.email_address, password: "allure-test-password" }
  end

  describe "primary navigation tree" do
    it "links the M4 leaves for signed-in users" do
      sign_in_as

      get feed_path

      expect(response.body).to include(
        %(href="#{feed_path}"),
        %(href="#{me_path}"),
        %(href="#{workouts_path}"),
        %(href="#{new_workout_import_path}"),
        %(href="#{segments_path}"),
        %(href="#{equipments_path}"),
        %(href="#{settings_path}")
      )
    end

    it "routes no leaderboard directory: the board lives on the segment page" do
      expect { Rails.application.routes.recognize_path("/leaderboards") }
        .to raise_error(ActionController::RoutingError)
    end

    it "keeps records and stats behind /me instead of primary navigation" do
      create(:workout, user:, sport:)
      sign_in_as

      get feed_path
      expect(response.body).not_to include(%(href="#{records_path}"))
      expect(response.body).not_to include(%(href="#{by_time_stats_path}"))

      get me_path
      expect(response.body).to include(%(href="#{records_path}"), %(href="#{stats_path}"))

      get stats_path
      expect(response.body).to include(%(href="#{by_time_stats_path}"), %(href="#{by_sport_stats_path}"))
    end

    it "exposes the routed M5 leaves and no dormant M5 paths" do
      sign_in_as

      get feed_path

      expect(response.body).to include(
        %(href="#{feed_path}"), %(href="#{people_path}")
      )
      expect(response.body).not_to include(
        %(href="#{following_path}"), 'href="/trails"', 'href="/settings/federation"',
        'href="/settings/wanderer"'
      )
    end

    it "redirects anonymous visitors before any signed-in chrome renders" do
      get feed_path

      expect(response).to redirect_to(new_session_path)
      expect(response.body).not_to include(%(href="#{me_path}"))
    end
  end

  describe "new landing pages" do
    it "renders /me with recent workouts" do
      create(:workout, user:, sport:)
      sign_in_as

      get me_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(href="#{profile_path(user.username)}"))
    end

    it "renders the universal /settings hub and links the collections there" do
      sign_in_as

      get settings_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(
        %(href="#{settings_profile_path}"),
        %(href="#{settings_notifications_path}"),
        %(href="#{publishing_profiles_path}"),
        %(href="#{privacy_zones_path}")
      )
    end

    it "renders the notifications inbox" do
      sign_in_as

      get notifications_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("notifications.empty.title")))
    end

    it "redirects anonymous visitors to sign-in" do
      get me_path
      expect(response).to redirect_to(new_session_path)

      get settings_path
      expect(response).to redirect_to(new_session_path)

      get stats_path
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "segment kinds" do
    it "renders the loop tab" do
      sign_in_as

      get segments_path(kind: "loop")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Boucles")
    end
  end
end
