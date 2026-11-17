# frozen_string_literal: true

require "rails_helper"

# The owner route image of a course (docs/dev/DERIVATIONS.md): served through the
# application at the course's own visibility, never as a raw storage URL.
RSpec.describe "Segment route images" do
  let(:owner) { create(:user) }
  let(:viewer) { create(:user) }
  let(:segment) { create(:segment, user: owner) }

  def attach_image(segment)
    segment.route_image.attach(
      io: StringIO.new("\x89PNG\r\n\x1A\nsegment".b),
      filename: "segment.png",
      content_type: "image/png"
    )
  end

  def follow(follower, followed)
    create(
      :following,
      :accepted,
      follower_actor: create(:actor, :local, user: follower),
      followed_actor: create(:actor, :local, user: followed)
    )
  end

  it "serves the PNG to the owner without exposing a storage URL" do
    attach_image(segment)
    sign_in_as(owner)

    get segment_route_image_path(segment)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("image/png")
    expect(response.headers["Cache-Control"]).to eq("private, no-store")
    expect(response.headers["Content-Disposition"]).to include("inline")
    expect(response.body).to start_with("\x89PNG".b)
    expect(response.body).not_to include("rails/active_storage")
  end

  it "serves a public course image to signed-in non-owners" do
    segment.update!(visibility: "public")
    attach_image(segment)

    sign_in_as(viewer)
    get segment_route_image_path(segment)
    expect(response).to have_http_status(:ok)
  end

  it "serves a followers-only course image to an accepted follower only" do
    segment.update!(visibility: "followers_only")
    attach_image(segment)

    get segment_route_image_path(segment)
    expect(response).to redirect_to(new_session_path)

    sign_in_as(viewer)
    get segment_route_image_path(segment)
    expect(response).to have_http_status(:not_found)

    follow(viewer, owner)
    get segment_route_image_path(segment)
    expect(response).to have_http_status(:ok)
  end

  it "never serves a private course image to anyone but its owner" do
    attach_image(segment)

    get segment_route_image_path(segment)
    expect(response).to redirect_to(new_session_path)

    sign_in_as(viewer)
    get segment_route_image_path(segment)
    expect(response).to have_http_status(:not_found)

    sign_in_as(owner)
    get segment_route_image_path(segment)
    expect(response).to have_http_status(:ok)
  end

  it "returns 404 while generation is pending" do
    sign_in_as(owner)

    get segment_route_image_path(segment)

    expect(response).to have_http_status(:not_found)
  end

  it "returns 404 for malformed, unknown, and integer identifiers" do
    sign_in_as(owner)

    get segment_route_image_path(segment_id: "invalid")
    expect(response).to have_http_status(:not_found)

    get segment_route_image_path(segment_id: "2222222222222222222222")
    expect(response).to have_http_status(:not_found)

    get segment_route_image_path(segment_id: segment.id)
    expect(response).to have_http_status(:not_found)
  end
end
