# frozen_string_literal: true

require "rails_helper"

# M4 Slice 3 proofs: one h1 per page, toast region, shared confirmation
# modal, per-sport icons, and accessible workout-card links.
RSpec.describe "Slice 3 shared components" do
  let(:user) { create(:user) }
  let(:sport) { create(:sport) }

  def one_h1(selector_count)
    expect(selector_count).to eq(1), "expected exactly one <h1> per page"
  end

  def publish(workout)
    create(:track_segment, workout:)
    profile = create(:publishing_profile, :without_endpoint_masks, user: workout.user)
    publish_workout!(user: workout.user, workout:, profile:)
  end

  describe "page headings" do
    it "renders exactly one h1 on key signed-in pages" do
      sign_in_as(user)
      create(:workout, user:, sport:)

      [ feed_path, me_path, workouts_path, settings_security_path ].each do |path|
        get path
        expect(response).to have_http_status(:ok)
        one_h1(response.body.scan(/<h1[\s>]/).size)
      end
    end

    it "renders exactly one h1 on auth and error pages" do
      get new_session_path
      expect(response).to have_http_status(:ok)
      one_h1(response.body.scan(/<h1[\s>]/).size)

      get "/404"
      expect(response).to have_http_status(:not_found)
      one_h1(response.body.scan(/<h1[\s>]/).size)
    end
  end

  describe "toast region" do
    it "exists in the layout from first paint" do
      sign_in_as(user)
      get feed_path

      expect(response.body).to include('id="toasts"', 'aria-live="polite"', 'data-controller="toasts"')
    end
  end

  describe "confirmation modal" do
    it "renders the shared modal once in the layout" do
      sign_in_as(user)
      get feed_path

      expect(response.body.scan(/id="confirm-modal"/).size).to eq(1)
      expect(response.body).to include('data-controller="confirm"', I18n.t("confirm_modal.cancel"))
    end

    it "carries title, body and verb on every destructive form" do
      sign_in_as(user)
      workout = create(:workout, user:, sport:)
      segment = create(:segment, user:, sport:)
      equipment = create(:equipment, user:)
      zone = create(:privacy_zone, user:)
      profile = create(:publishing_profile, :custom, user:)

      get workout_path(workout)
      expect(response.body).to include("data-confirm-title", "data-confirm-body", "data-confirm-verb")
      expect(response.body).to include(I18n.t("workouts.show.confirm.title"))
      expect(response.body).not_to include("turbo-confirm")

      get segment_path(segment)
      expect(response.body).to include(I18n.t("segments.show.confirm.title"))

      get equipment_path(equipment)
      expect(response.body).to include(I18n.t("equipments.actions.confirm.title"))

      get privacy_zones_path
      expect(response.body).to include(I18n.t("privacy_zones.actions.confirm.title"))

      get publishing_profiles_path
      expect(response.body).to include(I18n.t("publishing_profiles.actions.confirm.title"))
    end

    it "states the publication withdrawal consequence verbatim" do
      owner = create(:user)
      publishing_profile = create(:publishing_profile, :without_endpoint_masks, user: owner)
      workout = create(:workout, user: owner, sport:)
      create(:track_segment, workout:)
      publish_workout!(user: owner, workout:, profile: publishing_profile)
      sign_in_as(owner)

      get workout_path(workout)

      expect(response.body).to include(I18n.t("workouts.publication.confirm.title"))
      # Data attributes are HTML-escaped in the markup (apostrophes become
      # &#39;); compare against the escaped rendering.
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("workouts.publication.confirm.body")))
    end
  end

  describe "sport identity" do
    it "renders the per-sport SVG instead of a font glyph" do
      cycling = catalog_sport("cycling")
      publish(create(:workout, user:, sport: cycling, title: "Per-sport glyph"))
      sign_in_as(user)

      get feed_path

      expect(response.body).to include('viewBox="0 0 1000 1000"')
    end

    it "never renders the missing ski glyph" do
      ski = catalog_sport("skiing_alpine")
      publish(create(:workout, user:, sport: ski, title: "Ski glyph"))
      sign_in_as(user)

      get feed_path

      expect(response.body).not_to include("ti-skiing", "ti-ski-jumping")
      expect(response.body).to include('viewBox="0 0 1000 1000"')
    end

    it "renders custom sports as inline SVG" do
      rowing = catalog_sport("rowing")
      publish(create(:workout, user:, sport: rowing, title: "Row glyph"))
      sign_in_as(user)

      get feed_path

      expect(response.body).to include('viewBox="0 0 1000 1000"')
      expect(response.body).not_to include("ti-rowing")
    end
  end

  describe "workout cards" do
    it "labels the card link with the workout title" do
      publish(create(:workout, user:, sport:, title: "Distinct footer title"))
      sign_in_as(user)

      get feed_path

      expect(response.body).to include(%(aria-label="#{I18n.t("workouts.show.title")} : Distinct footer title"))
    end
  end
end
