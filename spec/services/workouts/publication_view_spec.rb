# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workouts::PublicationView do
  it "uses the supplied principal for the audience policy" do
    user = create(:user)
    workout = create(:workout, user:)
    profile = create(:publishing_profile, :followers, user:)
    publication = create(
      :workout_publication,
      workout:, publishing_profile: profile,
      representation: {
        "sport_slug" => workout.sport.slug,
        "started_at" => workout.started_at.iso8601(6),
        "metrics" => { "distance" => 1_000.0 },
        "track" => {
          "type" => "FeatureCollection",
          "features" => [
            {
              "type" => "Feature",
              "geometry" => { "type" => "LineString", "coordinates" => [ [ 6.4, 45.0 ], [ 6.5, 45.1 ] ] },
              "properties" => { "segment_index" => 0 }
            }
          ]
        }
      }
    )
    allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(true)

    owner_view = described_class.new(publication, principal: Workouts::PublicationPrincipal.browser(user))
    anonymous_view = described_class.new(publication)

    expect(owner_view.map_visible?).to be(true)
    expect(owner_view.metrics_present?).to be(true)
    expect(anonymous_view.map_visible?).to be(false)
  end
end
