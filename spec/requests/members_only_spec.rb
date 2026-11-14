# frozen_string_literal: true

require "rails_helper"

# PLAN_MEMBERS_ONLY.md: every browser surface requires a registered account, a
# shared link survives the sign-in gate, and the public wire contract stays
# anonymous for remote peers.
RSpec.describe "Members-only access" do
  let(:owner) { create(:user) }
  let(:viewer) { create(:user) }

  def publish_public(workout)
    create(:track_segment, workout:)
    profile = create(:publishing_profile, :without_endpoint_masks, user: workout.user)
    publish_workout!(user: workout.user, workout:, profile:)
  end

  it "returns a visitor to the shared workout link after sign-in" do
    workout = create(:workout, user: owner, title: "Shared ride")
    publish_public(workout)

    get workout_path(workout)
    expect(response).to redirect_to(new_session_path)

    sign_in_as(viewer)
    expect(response).to redirect_to(workout_path(workout))

    follow_redirect!
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Shared ride")
  end

  it "returns a visitor to the feed after sign-in" do
    get feed_path
    expect(response).to redirect_to(new_session_path)

    sign_in_as(viewer)
    expect(response).to redirect_to(feed_path)
  end

  it "keeps the public protocol object anonymously readable" do
    workout = create(:workout, user: owner)
    create(:track_segment, workout:)
    profile = create(:publishing_profile, :without_endpoint_masks, user: owner)
    publication = publish_workout!(user: owner, workout:, profile:)

    get workout_publication_path(publication)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/activity+json")
  end

  it "denies a public course to an anonymous browser and serves it to a member" do
    segment = create(:segment, user: owner, visibility: "public")

    get segment_path(segment)
    expect(response).to redirect_to(new_session_path)

    sign_in_as(viewer)
    get segment_path(segment)
    expect(response).to have_http_status(:ok)
  end
end
