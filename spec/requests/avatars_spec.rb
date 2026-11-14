# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Avatars" do
  let(:user) { create(:user, gravatar_opt_in: true) }

  before do
    user.gravatar_cache.attach(
      io: StringIO.new("cached-avatar"),
      filename: "gravatar.jpg",
      content_type: "image/jpeg"
    )
    sign_in_as(create(:user))
  end

  it "redirects an anonymous visitor to sign-in" do
    delete session_path

    get profile_avatar_path(user.username)

    expect(response).to redirect_to(new_session_path)
  end

  it "serves the cached avatar through the application" do
    get profile_avatar_path(user.username)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("image/jpeg")
    expect(response.headers["Cache-Control"]).to eq("private, no-store")
    expect(response.headers["Content-Disposition"]).to include("inline")
    expect(response.body).to eq("cached-avatar")
  end

  it "returns 404 for an unknown account" do
    get profile_avatar_path("missing")

    expect(response).to have_http_status(:not_found)
  end

  it "serves an uploaded avatar in preference to the cached Gravatar" do
    user.avatar.attach(io: StringIO.new("uploaded-avatar"), filename: "avatar.webp", content_type: "image/webp")

    get profile_avatar_path(user.username)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("image/webp")
    expect(response.body).to eq("uploaded-avatar")
  end

  it "serves an uploaded avatar without Gravatar opt-in" do
    uploader = create(:user)
    uploader.avatar.attach(io: StringIO.new("uploaded-avatar"), filename: "avatar.webp", content_type: "image/webp")

    get profile_avatar_path(uploader.username)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("image/webp")
  end

  it "returns 404 when the account has no cached avatar" do
    other_user = create(:user, gravatar_opt_in: true)

    get profile_avatar_path(other_user.username)

    expect(response).to have_http_status(:not_found)
  end

  it "returns 404 for a stale cache after opt-out" do
    user.update_column(:gravatar_opt_in, false)

    get profile_avatar_path(user.username)

    expect(response).to have_http_status(:not_found)
  end

  it "uses the application proxy in rendered pages" do
    sign_in_as(user)

    get feed_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(%(src="#{profile_avatar_path(user.username)}"))
    expect(response.body).not_to include("/rails/active_storage", user.gravatar_cache.blob.key)
  end
end
