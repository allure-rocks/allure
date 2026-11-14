# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Segment charts" do
  let(:owner) { create(:user) }
  let(:viewer) { create(:user) }
  let(:sport) { create(:sport) }
  let(:workout) { create(:workout, user: owner, sport:, points_count: 3, distance: 200.0) }

  before do
    create(
      :track_segment,
      workout:,
      position: 0,
      distance: 200.0,
      points: [
        { "t" => 0, "d" => 0.0, "lat" => 45.0710, "lon" => 6.4074, "ele" => 100.0 },
        { "t" => 30, "d" => 100.0, "lat" => 45.0710, "lon" => 6.4084, "ele" => 105.0 },
        { "t" => 60, "d" => 200.0, "lat" => 45.0710, "lon" => 6.4094, "ele" => 110.0 }
      ]
    )
  end

  let(:segment) do
    Segments::Creator.new(user: owner, workout:, name: "Profil", start_index: 0, end_index: 2).call
  end

  def sign_in(user)
    post session_path, params: { email_address: user.email_address, password: "allure-test-password" }
  end

  it "serves the stored profile to the owner without any source timing" do
    sign_in(owner)

    get segment_chart_path(segment)

    expect(response).to have_http_status(:ok)
    expect(response.headers["Cache-Control"]).to eq("private, no-store")
    expect(response.parsed_body["points"]).to eq(
      [
        { "distance" => 0.0, "elevation" => 100.0 },
        { "distance" => 100.0, "elevation" => 105.0 },
        { "distance" => 200.0, "elevation" => 110.0 }
      ]
    )
    expect(response.body).not_to include("elapsed_time")
  end

  it "serves a public course profile to a signed-in non-owner" do
    segment.update!(visibility: "public")
    sign_in(viewer)

    get segment_chart_path(segment)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["points"].length).to eq(3)
  end

  it "404s a non-owner while private and redirects an anonymous visitor" do
    sign_in(viewer)
    get segment_chart_path(segment)
    expect(response).to have_http_status(:not_found)

    delete session_path
    get segment_chart_path(segment)
    expect(response).to redirect_to(new_session_path)
  end

  it "allows an accepted local follower on a followers-only course" do
    segment.update!(visibility: "followers_only")
    create(:local_actor, user: owner)
    create(:local_actor, user: viewer)
    create(:following, :accepted, follower_actor: viewer.actor, followed_actor: owner.actor)
    sign_in(viewer)

    get segment_chart_path(segment)

    expect(response).to have_http_status(:ok)
  end

  it "returns an empty profile for a course without a stored profile" do
    plain = create(:segment, user: owner, sport:)
    sign_in(owner)

    get segment_chart_path(plain)

    expect(response.parsed_body["points"]).to eq([])
  end

  it "keeps serving the stored profile after the source workout is deleted" do
    segment
    segment.update_columns(source_workout_id: nil)
    sign_in(owner)

    get segment_chart_path(segment)

    expect(response.parsed_body["points"].length).to eq(3)
  end
end
