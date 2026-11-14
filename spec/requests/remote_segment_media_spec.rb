# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Remote segment media" do
  let(:author) { create(:actor, uri: "https://remote.example/users/demo") }
  let(:viewer) { create(:user) }
  let(:representation) do
    {
      "name" => "Col du Test",
      "kind" => "segment",
      "distance" => 2500.0,
      "track" => {
        "type" => "FeatureCollection",
        "features" => [
          { "type" => "Feature",
            "geometry" => { "type" => "LineString", "coordinates" => [ [ 6.4074, 45.071 ], [ 6.4092, 45.0728 ] ] },
            "properties" => { "segment_index" => 0 } }
        ]
      }
    }
  end
  let(:segment) { create(:remote_segment, actor: author, representation:) }

  before do
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("<gpx/>"), filename: "course.gpx",
      content_type: "application/xml+gpx", identify: false
    )
    create(:remote_segment_attachment, remote_segment: segment, kind: "gpx", status: "cached", blob:)

    image = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("png-bytes"), filename: "course.png",
      content_type: "image/png", identify: false
    )
    create(:remote_segment_attachment, remote_segment: segment, kind: "route_image", status: "cached", blob: image)
  end

  def sign_in_as(user)
    post session_path, params: { email_address: user.email_address, password: "allure-test-password" }
  end

  it "requires a session" do
    get remote_segment_gpx_path(segment)

    expect(response).to redirect_to(new_session_path)
  end

  it "serves the cached GPX and route image with private cache headers" do
    sign_in_as(viewer)

    get remote_segment_gpx_path(segment)
    expect(response).to have_http_status(:ok)
    expect(response.headers["Cache-Control"]).to eq("private, no-store")
    expect(response.media_type).to eq("application/xml+gpx")

    get remote_segment_route_image_path(segment)
    expect(response).to have_http_status(:ok)
    expect(response.headers["Cache-Control"]).to eq("private, no-store")
    expect(response.media_type).to eq("image/png")
  end

  it "serves the requested image variant and falls back to the cached one" do
    sign_in_as(viewer)

    get remote_segment_route_image_path(segment, theme: "dark")
    expect(response).to have_http_status(:ok)
    expect(response.body).to eq("png-bytes")

    dark = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("png-dark-bytes"), filename: "course-dark.png",
      content_type: "image/png", identify: false
    )
    create(:remote_segment_attachment, remote_segment: segment, kind: "route_image",
                                       theme: "dark", status: "cached", blob: dark)

    get remote_segment_route_image_path(segment, theme: "dark")
    expect(response).to have_http_status(:ok)
    expect(response.body).to eq("png-dark-bytes")
  end

  it "serves the track as a FeatureCollection" do
    sign_in_as(viewer)

    get remote_segment_track_path(segment)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/geo+json")
    expect(response.headers["Cache-Control"]).to eq("private, no-store")
    expect(JSON.parse(response.body).fetch("type")).to eq("FeatureCollection")
  end

  it "returns 404 for pending or purged media" do
    segment.attachments.update_all(status: "pending", blob_id: nil)
    sign_in_as(viewer)

    get remote_segment_gpx_path(segment)
    expect(response).to have_http_status(:not_found)
  end

  it "returns 404 for a deleted course" do
    segment.mark_deleted!
    sign_in_as(viewer)

    get remote_segment_gpx_path(segment)
    get remote_segment_track_path(segment)

    expect(response).to have_http_status(:not_found)
  end

  it "requires an entitlement for a followers-only course" do
    segment.update_columns(audience: "followers")
    sign_in_as(viewer)

    get remote_segment_gpx_path(segment)
    expect(response).to have_http_status(:not_found)

    create(
      :remote_segment_recipient,
      remote_segment: segment,
      recipient_actor: Federation::ActorProvisioner.new(user: viewer).call!
    )

    get remote_segment_gpx_path(segment)
    expect(response).to have_http_status(:ok)
  end
end
