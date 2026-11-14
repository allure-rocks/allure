# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Workout tracks" do
  let(:owner) { create(:user) }
  let(:workout) { create(:workout, user: owner) }

  # The factory derives geom from points, so overriding points keeps the two
  # consistent. Overriding geom alone would leave them describing different
  # routes.
  def points_at(coordinates, elevations: nil, speeds: nil)
    coordinates.each_with_index.map do |(lon, lat), index|
      { "t" => index * 60, "d" => index * 250.0, "lat" => lat, "lon" => lon }.tap do |point|
        point["ele"] = elevations[index] if elevations
        point["v"] = speeds[index] if speeds
      end
    end
  end

  it "returns an exact ordered GeoJSON FeatureCollection to the owner" do
    create(:track_segment, workout:, position: 0)
    create(:track_segment, workout:, position: 1,
           points: points_at([ [ 6.411, 45.0745 ], [ 6.4131, 45.0761 ] ], elevations: [ 120.0, 130.0 ]))
    sign_in_as(owner)

    get workout_track_path(workout)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/geo+json")
    expect(response.headers["Cache-Control"]).to eq("private, no-store")
    expect(JSON.parse(response.body)).to eq(
      "type" => "FeatureCollection",
      "features" => [
        {
          "type" => "Feature",
          "geometry" => { "type" => "LineString",
                          "coordinates" => [ [ 6.4074, 45.071 ], [ 6.4092, 45.0728 ] ] },
          "properties" => { "segment_index" => 0,
                            "distance" => [ 0.0, 250.0 ],
                            "elevation" => [ 100.0, 112.0 ] }
        },
        {
          "type" => "Feature",
          "geometry" => { "type" => "LineString",
                          "coordinates" => [ [ 6.411, 45.0745 ], [ 6.4131, 45.0761 ] ] },
          "properties" => { "segment_index" => 1,
                            "distance" => [ 250.0, 500.0 ],
                            "elevation" => [ 120.0, 130.0 ] }
        }
      ]
    )
  end

  it "keeps one Feature per recording segment so a pause draws no connecting line" do
    create(:track_segment, workout:, position: 0)
    create(:track_segment, workout:, position: 1,
           points: points_at([ [ 6.411, 45.0745 ], [ 6.4131, 45.0761 ] ]))
    sign_in_as(owner)

    get workout_track_path(workout)

    features = JSON.parse(response.body).fetch("features")
    expect(features.length).to eq(2)
    expect(features.map { it.dig("geometry", "coordinates").length }).to eq([ 2, 2 ])
  end

  it "carries speed when it was recorded and omits it entirely when it was not" do
    create(:track_segment, workout:,
           points: points_at([ [ 6.4074, 45.071 ], [ 6.4092, 45.0728 ] ], speeds: [ 2.5, 3.25 ]))
    sign_in_as(owner)

    get workout_track_path(workout)
    expect(JSON.parse(response.body).dig("features", 0, "properties", "speed")).to eq([ 2.5, 3.25 ])

    workout.track_segments.destroy_all
    create(:track_segment, workout:, points: points_at([ [ 6.4074, 45.071 ], [ 6.4092, 45.0728 ] ]))

    get workout_track_path(workout)
    expect(JSON.parse(response.body).dig("features", 0, "properties")).not_to have_key("speed")
  end

  it "serves sanitized track data to a signed-in member when the publication includes the route" do
    create(:track_segment, workout:)
    profile = create(:publishing_profile, :without_endpoint_masks, user: owner, settings: PublishingProfile::DEFAULT_SETTINGS.merge("route" => true, "mask_start" => false, "mask_finish" => false))
    publish_workout!(user: owner, workout:, profile:)
    sign_in_as(create(:user))

    get workout_track_path(workout)
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/geo+json")
  end

  it "redirects an anonymous visitor to sign-in" do
    create(:track_segment, workout:)

    get workout_track_path(workout)

    expect(response).to redirect_to(new_session_path)
  end

  it "returns 404 for malformed, unknown, and integer identifiers" do
    sign_in_as(owner)

    get workout_track_path(workout_id: "invalid")
    expect(response).to have_http_status(:not_found)

    get workout_track_path(workout_id: "2222222222222222222222")
    expect(response).to have_http_status(:not_found)

    get workout_track_path(workout_id: workout.id)
    expect(response).to have_http_status(:not_found)
  end
end
