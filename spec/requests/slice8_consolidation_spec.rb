# frozen_string_literal: true

require "rails_helper"

# Slice 8 consolidation proofs: dormant navigation is gone, JS strings are
# bilingual via data attributes, empty states offer actions, the shared
# residual-risk panel sits above ranked rows, and form errors announce.
RSpec.describe "Slice 8 consolidation" do
  let(:user) { create(:user) }
  let(:sport) { create(:sport) }

  def sign_in_as(u = user)
    post session_path, params: { email_address: u.email_address, password: "allure-test-password" }
  end

  describe "navigation" do
    it "links M4 leaves and no dormant paths for signed-in users" do
      sign_in_as

      get feed_path

      expect(response.body).to include(
        %(href="#{feed_path}"), %(href="#{me_path}"),
        %(href="#{workouts_path}"), %(href="#{new_workout_import_path}"),
        %(href="#{segments_path}"),
        %(href="#{equipments_path}"), %(href="#{settings_path}"), %(href="#{people_path}")
      )
      expect(response.body).not_to include(
        %(href="#{following_path}"), 'href="/trails"', 'href="/settings/federation"',
        'href="/settings/wanderer"'
      )
    end

    it "keeps records and stats behind /me" do
      create(:workout, user:, sport:)
      sign_in_as

      get feed_path
      expect(response.body).not_to include(%(href="#{records_path}"))

      get me_path
      expect(response.body).to include(%(href="#{records_path}"), %(href="#{stats_path}"))
    end

    it "redirects anonymous visitors before any signed-in chrome renders" do
      get feed_path

      expect(response).to redirect_to(new_session_path)
      expect(response.body).not_to include(%(href="#{me_path}"))
    end
  end

  describe "bilingual JS strings" do
    it "passes translated calendar strings via data attributes" do
      create(:workout, user:, sport:)
      sign_in_as

      get me_path

      expect(response.body).to include(%(data-calendar-label-value="Calendrier d&#39;activité"))
      expect(response.body).to include('data-calendar-workout-one-value="activité"')
      expect(response.body).to include('data-calendar-workout-other-value="activités"')
    end

    it "passes the translated series name to stats charts" do
      create(:workout, user:, sport:)
      sign_in_as

      get by_time_stats_path(time: "month")

      expect(response.body).to include('data-stats-chart-distance-label-value="Distance"')
    end
  end

  describe "empty actions" do
    it "offers import from empty records and stats" do
      sign_in_as

      get records_path
      expect(response.body).to include(%(href="#{new_workout_import_path}"))

      get by_time_stats_path(time: "month")
      expect(response.body).to include(%(href="#{new_workout_import_path}"))
    end

    it "renders shared empties as components" do
      owner = create(:user)
      segment = create(:segment, user: owner, sport:, visibility: "public")
      sign_in_as(create(:user))

      get segment_leaderboard_path(segment)

      expect(response.body).to include("Aucun participant pour le moment")
    end
  end

  describe "shared residual panel and ranks" do
    it "shows the full notice above ranked pseudonymous rows" do
      owner = create(:user)
      athlete = create(:user)
      segment = create(:segment, user: owner, sport:, visibility: "public")
      workout = create(:workout, user: athlete, sport:)
      create(:workout_publication, workout:, publishing_profile: public_publishing_profile_for(athlete), status: "active")
      create(:segment_effort, segment:, workout:, user: athlete, sport:)
      sign_in_as(create(:user))

      get segment_leaderboard_path(segment)
      body = response.body

      expect(body).to include("alert-info")
      expect(body).to include("réduites au mois", "donnée personnelle")
      expect(body).to include("Rang")
      expect(body.index("alert-info")).to be < body.index("<table")
      expect(body).to include("allure-medal--gold", I18n.t("medals.rank", rank: 1))
    end
  end

  describe "form error announcement" do
    it "announces equipment errors" do
      type = create(:equipment_type)
      sign_in_as

      post equipments_path, params: { equipment: { label: "", equipment_type_id: type.id } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('role="alert"')
    end

    it "announces segment errors" do
      segment = create(:segment, user:, sport:)
      sign_in_as

      patch segment_path(segment), params: { segment: { name: "" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('role="alert"')
    end

    it "announces settings errors" do
      sign_in_as

      patch settings_units_path, params: { user: { time_zone: "not-a-zone" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('role="alert"')
    end
  end
end
