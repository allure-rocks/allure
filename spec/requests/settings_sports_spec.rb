# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Settings sports" do
  let(:user) { create(:user) }

  before do
    catalog_sport("cycling")
    catalog_sport("running")
    catalog_sport("walking")
    sign_in_as(user)
  end

  it "renders the generic itself and only the curated variants for each generic" do
    catalog_sport("cycling_road")
    catalog_sport("running_virtual")
    catalog_sport("trail")
    catalog_sport("hiking")
    catalog_sport("tennis_outdoor")

    get settings_sports_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(
      I18n.t("settings.sports.card_title"),
      "Vélo",
      "Vélo route",
      "Course à pied",
      "Course à pied (virtuelle)",
      "Marche",
      "Randonnée"
    )
    # Same icon family is not enough: tennis and padel are never running
    # defaults, halfbike is never a cycling one.
    expect(response.body).not_to include("Tennis en extérieur", "Padel en extérieur", "Halfbike")
  end

  it "preselects the generic sport when no preference is stored" do
    catalog_sport("cycling_road")

    get settings_sports_path

    selected = Nokogiri::HTML(response.body).css("select").map do |select|
      select.css("option[selected]").map(&:text)
    end

    expect(selected).to eq([ [ "Vélo" ], [ "Course à pied" ], [ "Marche" ] ])
  end

  it "stores the preselected generic when the form is saved untouched" do
    get settings_sports_path
    selected = Nokogiri::HTML(response.body).css("select option[selected]").map { it["value"] }

    patch settings_sports_path, params: {
      user: {
        default_cycling_sport_id: selected[0],
        default_running_sport_id: selected[1],
        default_walking_sport_id: selected[2]
      }
    }

    expect(response).to redirect_to(settings_sports_path)
    expect(user.reload.default_cycling_sport.slug).to eq("cycling")
    expect(user.reload.default_running_sport.slug).to eq("running")
    expect(user.reload.default_walking_sport.slug).to eq("walking")
  end

  it "saves the chosen variants" do
    cycling_road = catalog_sport("cycling_road")
    trail = catalog_sport("trail")

    patch settings_sports_path, params: {
      user: { default_cycling_sport_id: cycling_road.id, default_running_sport_id: trail.id }
    }

    expect(response).to redirect_to(settings_sports_path)
    expect(user.reload.default_cycling_sport).to eq(cycling_road)
    expect(user.reload.default_running_sport).to eq(trail)
  end

  it "rejects a target outside the generic's family" do
    rowing = catalog_sport("rowing")

    patch settings_sports_path, params: { user: { default_cycling_sport_id: rowing.id } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(user.reload.default_cycling_sport).to be_nil
  end

  it "links the page from the settings shell" do
    get settings_profile_path
    expect(response.body).to include(%(href="#{settings_sports_path}"))
  end
end
