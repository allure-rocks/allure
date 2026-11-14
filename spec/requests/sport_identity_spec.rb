# frozen_string_literal: true

require "rails_helper"

# DESIGN.md §6: sport identity is icon + text on a brand-tinted tile. Colour
# never encodes a sport, on any surface.
RSpec.describe "Sport identity" do
  let(:user) { create(:user) }

  def publish(workout, owner)
    profile = create(:publishing_profile, :without_endpoint_masks, user: owner)
    publish_workout!(user: owner, workout:, profile:)
  end

  it "renders a brand-tinted sport tile and never a per-sport hue" do
    workout = create(:workout, user:, sport: catalog_sport("running"), title: "Tiled run")
    create(:track_segment, workout:)
    publish(workout, user)
    sign_in_as(create(:user))

    get feed_path

    expect(response.body).to include("sport-tile", "avatar-square")
    # The icon set is migrating to the 1000×1000 grid (DESIGN.md §6.4).
    expect(response.body).to match(/viewBox="0 0 (?:24 24|1000 1000)"/)
    expect(response.body).not_to include("ti-run")
    # #0ca678 was the old run family colour; the avatar palette never uses it.
    expect(response.body).not_to include("#0ca678")
  end

  it "strips sport colour from the map, summary accent and elevation chart" do
    workout = create(:workout, user:)
    create(:track_segment, workout:)
    sign_in_as(user)

    get workout_path(workout)

    expect(response.body).not_to include(
      "data-map-color-value", "data-elevation-chart-color-value", "--allure-workout-color"
    )
  end

  it "renders the /me progress bars without a sport background" do
    create(:workout, user:, distance: 5_000, started_at: 20.days.ago)
    create(:workout, user:, distance: 5_000, started_at: 2.days.ago)
    sign_in_as(user)

    get me_path

    expect(response.body).to include("progress-bar")
    expect(response.body).not_to match(/progress-bar[^>]*background-color/)
  end

  it "is not a model attribute" do
    expect(create(:sport)).not_to respond_to(:colour)
    expect(Allure::SportPalette).not_to respond_to(:colour)
  end
end
