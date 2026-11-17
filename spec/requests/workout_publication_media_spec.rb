# frozen_string_literal: true

require "rails_helper"

# The signed wire endpoints under /api/v1: unsigned public fetches stay
# allowed — remote peers have no Allure account (docs/dev/ACCESS.md). The
# browser-facing counterpart has its own coverage in publication_media_spec.rb.
RSpec.describe "Workout publication media" do
  let(:owner) { create(:user) }
  let(:workout) { create(:workout, user: owner) }
  let(:profile) do
    create(
      :publishing_profile,
      user: owner,
      settings: PublishingProfile::DEFAULT_SETTINGS.merge("gpx" => true, "route_image" => true)
    )
  end
  let(:gpx_blob) do
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("<?xml version=\"1.0\"?><gpx />"),
      filename: "sanitized.gpx",
      content_type: "application/gpx+xml"
    )
  end
  let(:route_image_blob) do
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("\x89PNG\r\n\x1A\nroute".b),
      filename: "sanitized.png",
      content_type: "image/png"
    )
  end
  let(:publication) do
    create(
      :workout_publication,
      workout:,
      publishing_profile: profile,
      sanitized_gpx_blob_id: gpx_blob.id,
      sanitized_route_image_blob_id: route_image_blob.id
    )
  end

  before do
    publication.gpx.attach(gpx_blob)
    publication.route_image.attach(route_image_blob)
  end

  it "serves active public publication media anonymously" do
    get workout_publication_gpx_path(publication)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/gpx+xml")
    expect(response.headers["Cache-Control"]).to eq("private, no-store")
    expect(response.headers["Content-Disposition"]).to include("attachment")
    expect(response.body).to include("<gpx")

    get workout_publication_route_image_path(publication)
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("image/png")
  end

  it "serves the dark route image on its own signed path" do
    dark_blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("\x89PNG\r\n\x1A\ndark".b),
      filename: "sanitized-dark.png",
      content_type: "image/png"
    )
    publication.route_image_dark.attach(dark_blob)
    WorkoutPublication.where(id: publication.id).update_all(sanitized_route_image_dark_blob_id: dark_blob.id)

    get workout_publication_route_image_dark_path(publication)
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("image/png")
    expect(response.body).to end_with("dark".b)

    get workout_publication_route_image_path(publication)
    expect(response.body).to end_with("route".b)
  end

  it "falls back to the light image on the dark path" do
    get workout_publication_route_image_dark_path(publication)

    expect(response).to have_http_status(:ok)
    expect(response.body).to end_with("route".b)
  end

  it "does not expose followers media without a verified follower" do
    followers_profile = create(
      :publishing_profile,
      :followers,
      user: owner,
      settings: PublishingProfile::DEFAULT_SETTINGS.merge("gpx" => true)
    )
    followers_publication = create(
      :workout_publication,
      workout: create(:workout, user: owner),
      publishing_profile: followers_profile
    )
    followers_publication.gpx.attach(io: StringIO.new("gpx"), filename: "route.gpx", content_type: "application/gpx+xml")

    get workout_publication_gpx_path(followers_publication)

    expect(response).to have_http_status(:not_found)
  end

  it "returns 404 for deleted publications" do
    publication.mark_deleted!

    get workout_publication_gpx_path(publication)

    expect(response).to have_http_status(:not_found)
  end

  it "returns 404 when a publication attachment no longer matches its immutable blob reference" do
    publication.gpx.attach(
      io: StringIO.new("replacement"),
      filename: "replacement.gpx",
      content_type: "application/gpx+xml"
    )

    get workout_publication_gpx_path(publication)

    expect(response).to have_http_status(:not_found)
  end
end
