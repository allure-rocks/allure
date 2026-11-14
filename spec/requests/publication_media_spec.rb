# frozen_string_literal: true

require "rails_helper"

# The browser-facing publication media surface. The signed wire endpoints have
# their own coverage in workout_publication_media_spec.rb; this one proves the
# local principal path: a signed-in member for a public publication, the owner
# and an accepted local follower for a followers-only one (PLAN_M5 §13.2).
# Anonymous visitors are redirected to sign-in (PLAN_MEMBERS_ONLY.md).
RSpec.describe "Publication media" do
  let(:owner) { create(:user) }
  let(:workout) { create(:workout, user: owner) }
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
  let(:public_profile) do
    create(
      :publishing_profile,
      user: owner,
      settings: PublishingProfile::DEFAULT_SETTINGS.merge("gpx" => true)
    )
  end
  let(:followers_profile) do
    create(
      :publishing_profile,
      :followers,
      user: owner,
      settings: PublishingProfile::DEFAULT_SETTINGS.merge("gpx" => true)
    )
  end

  def published(profile)
    publication = create(
      :workout_publication,
      workout:,
      publishing_profile: profile,
      sanitized_gpx_blob_id: gpx_blob.id,
      sanitized_route_image_blob_id: route_image_blob.id
    )
    publication.gpx.attach(gpx_blob)
    publication.route_image.attach(route_image_blob)
    publication
  end

  it "serves a public publication's route image and sanitized GPX to a signed-in member" do
    publication = published(public_profile)
    sign_in_as(create(:user))

    get publication_route_image_path(publication)
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("image/png")
    expect(response.headers["Cache-Control"]).to eq("private, no-store")
    expect(response.headers["Content-Disposition"]).to include("inline")

    get publication_gpx_path(publication)
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/gpx+xml")
    expect(response.headers["Content-Disposition"]).to include("attachment")
    expect(response.body).to include("<gpx")
  end

  it "redirects an anonymous visitor to sign-in" do
    publication = published(public_profile)

    get publication_route_image_path(publication)

    expect(response).to redirect_to(new_session_path)
  end

  it "serves the dark variant and falls back to the light one" do
    publication = published(public_profile)
    sign_in_as(create(:user))

    get publication_route_image_path(publication, theme: "dark")
    expect(response).to have_http_status(:ok)
    expect(response.body).to end_with("route".b)

    dark_blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("\x89PNG\r\n\x1A\ndark".b),
      filename: "sanitized-dark.png",
      content_type: "image/png"
    )
    publication.route_image_dark.attach(dark_blob)
    WorkoutPublication.where(id: publication.id).update_all(sanitized_route_image_dark_blob_id: dark_blob.id)

    get publication_route_image_path(publication, theme: "dark")
    expect(response).to have_http_status(:ok)
    expect(response.body).to end_with("dark".b)
  end

  it "serves a followers-only publication to its owner" do
    allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(true)
    publication = published(followers_profile)
    sign_in_as(owner)

    get publication_route_image_path(publication)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("image/png")
  end

  it "serves a followers-only publication to an accepted local follower" do
    allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(true)
    Federation::ActorProvisioner.new(user: owner).call!
    publication = published(followers_profile)
    follower = create(:user)
    follower_actor = Federation::ActorProvisioner.new(user: follower).call!
    create(:following, :accepted, follower_actor:, followed_actor: owner.reload.actor)
    sign_in_as(follower)

    get publication_route_image_path(publication)

    expect(response).to have_http_status(:ok)
  end

  it "hides a followers-only publication from unrelated accounts" do
    allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(true)
    publication = published(followers_profile)
    sign_in_as(create(:user))

    get publication_route_image_path(publication)
    expect(response).to have_http_status(:not_found)

    get publication_gpx_path(publication)
    expect(response).to have_http_status(:not_found)
  end

  it "returns 404 for a deleted publication" do
    publication = published(public_profile)
    publication.mark_deleted!
    sign_in_as(create(:user))

    get publication_route_image_path(publication)

    expect(response).to have_http_status(:not_found)
  end

  it "returns 404 when an attachment no longer matches its immutable blob reference" do
    publication = published(public_profile)
    publication.route_image.attach(
      io: StringIO.new("replacement"),
      filename: "replacement.png",
      content_type: "image/png"
    )
    sign_in_as(create(:user))

    get publication_route_image_path(publication)

    expect(response).to have_http_status(:not_found)
  end

  it "returns 404 for malformed and unknown identifiers" do
    sign_in_as(create(:user))

    get publication_route_image_path(id: "invalid")
    expect(response).to have_http_status(:not_found)

    get publication_gpx_path(id: Allure::ShortId.encode(SecureRandom.uuid))
    expect(response).to have_http_status(:not_found)
  end
end
