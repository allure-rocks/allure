# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Remote avatars" do
  let(:actor) do
    create(
      :actor,
      uri: "https://remote.example/users/demo",
      handle: "demo@remote.example",
      acct: "demo@remote.example",
      avatar_url: "https://remote.example/avatar.png"
    )
  end

  before { sign_in_as(create(:user)) }

  it "redirects an anonymous visitor to sign-in" do
    delete session_path
    cache_avatar

    get remote_profile_avatar_path(actor.acct)

    expect(response).to redirect_to(new_session_path)
  end

  it "serves the cached avatar through the application with private caching" do
    actor.avatar_cache.attach(
      io: StringIO.new("\x89PNG\r\n\x1a\n".b),
      filename: "actor.png",
      content_type: "image/png"
    )

    get remote_profile_avatar_path(actor.acct)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("image/png")
    expect(response.headers["Cache-Control"]).to eq("private, no-store")
  end

  it "404s when no avatar is cached" do
    get remote_profile_avatar_path(actor.acct)

    expect(response).to have_http_status(:not_found)
  end

  it "404s a blocked actor even when an avatar is cached" do
    cache_avatar
    create(:federation_actor_block, actor_uri: actor.uri)

    get remote_profile_avatar_path(actor.acct)

    expect(response).to have_http_status(:not_found)
  end

  it "404s an actor on a blocked authority even when an avatar is cached" do
    cache_avatar
    create(:federation_domain_block, domain: "remote.example")

    get remote_profile_avatar_path(actor.acct)

    expect(response).to have_http_status(:not_found)
  end

  it "404s a tombstoned actor even when an avatar is cached" do
    cache_avatar
    actor.tombstone!

    get remote_profile_avatar_path(actor.acct)

    expect(response).to have_http_status(:not_found)
  end

  it "404s an unknown handle" do
    get remote_profile_avatar_path("nobody@remote.example")

    expect(response).to have_http_status(:not_found)
  end

  def cache_avatar
    actor.avatar_cache.attach(
      io: StringIO.new("\x89PNG\r\n\x1a\n".b),
      filename: "actor.png",
      content_type: "image/png"
    )
  end
end
