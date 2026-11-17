# frozen_string_literal: true

require "rails_helper"

# The Découvrir map endpoint (docs/dev/SEGMENTS.md): every course the viewer
# may see — the readable shared ones and their own, private ones included —
# inside the requested viewport, as sanitized GeoJSON. Facts only — no effort,
# no athlete, no source workout — and a malformed viewport is a client error,
# never a PostGIS failure.
RSpec.describe "Segment discover map" do
  let(:viewer) { create(:user) }
  let(:owner) { create(:user) }
  let(:sport) { create(:sport) }
  let(:bbox) { "6.40,45.06,6.42,45.08" }

  def sign_in(user)
    post session_path, params: { email_address: user.email_address, password: "allure-test-password" }
  end

  def follow(follower, followed)
    create(
      :following,
      :accepted,
      follower_actor: create(:actor, :local, user: follower),
      followed_actor: create(:actor, :local, user: followed)
    )
  end

  def features(response)
    JSON.parse(response.body).fetch("features")
  end

  it "requires a session" do
    get segments_discover_map_path(bbox:)

    expect(response).to redirect_to(new_session_path)
  end

  context "signed in" do
    before { sign_in(viewer) }

    it "returns the readable courses intersecting the viewport with their facts" do
      segment = create(:segment, user: owner, sport:, visibility: "public", name: "Col partagé")

      get segments_discover_map_path(bbox:)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/geo+json")
      expect(response.headers["Cache-Control"]).to eq("private, no-store")

      feature = features(response).first
      expect(feature.dig("geometry", "type")).to eq("LineString")
      expect(feature.dig("geometry", "coordinates").length).to be >= 2
      expect(feature.fetch("properties")).to include(
        "name" => "Col partagé",
        "sport" => sport.label,
        "url" => segment_path(segment)
      )
      expect(feature.dig("properties", "distance")).to be_present
      expect(feature.dig("properties", "participants")).to be_present
    end

    it "counts the participants the viewer sees ranked, never an unpublished effort" do
      segment = create(:segment, user: owner, sport:, visibility: "public")
      athlete = create(:user)
      workout = create(:workout, user: athlete, sport:)
      create(:segment_effort, segment:, workout:, user: athlete, sport:)
      segment.update_column(:athletes_count, 1)

      get segments_discover_map_path(bbox:)
      expect(features(response).first.dig("properties", "participants"))
        .to eq(I18n.t("segments.card.participants", count: 0))

      profile = build(:publishing_profile, user: athlete)
      profile.settings = profile.settings.merge("route" => true)
      create(:workout_publication, workout:, publishing_profile: profile, status: "active")

      get segments_discover_map_path(bbox:)
      expect(features(response).first.dig("properties", "participants"))
        .to eq(I18n.t("segments.card.participants", count: 1))
    end

    it "counts the efforts of the viewer's own private course" do
      segment = create(:segment, user: viewer, sport:, visibility: "private")
      create(:segment_effort, segment:, workout: create(:workout, user: viewer, sport:), user: viewer, sport:)

      get segments_discover_map_path(bbox:)

      expect(features(response).first.dig("properties", "participants"))
        .to eq(I18n.t("segments.card.participants", count: 1))
    end

    it "includes the viewer's own courses, private ones included" do
      create(:segment, user: viewer, sport:, visibility: "private", name: "Ma boucle privée")
      create(:segment, user: viewer, sport:, visibility: "public", name: "Mon col public")

      get segments_discover_map_path(bbox:)

      expect(features(response).map { |feature| feature.dig("properties", "name") })
        .to contain_exactly("Ma boucle privée", "Mon col public")
    end

    it "never leaks a course outside the viewport or a private course of someone else" do
      create(:segment, user: owner, sport:, visibility: "public", name: "Col hors zone",
                       geom: geographic_factory.line_string([
                         geographic_factory.point(2.35, 48.85), geographic_factory.point(2.36, 48.86)
                       ]))
      create(:segment, user: owner, sport:, visibility: "private", name: "Col privé")

      get segments_discover_map_path(bbox:)

      expect(features(response)).to be_empty
    end

    it "hides a followers-only course from a non-follower and serves an accepted one" do
      create(:segment, user: owner, sport:, visibility: "followers_only", name: "Col des abonnés")

      get segments_discover_map_path(bbox:)
      expect(features(response)).to be_empty

      follow(viewer, owner)
      get segments_discover_map_path(bbox:)
      expect(features(response).map { |feature| feature.dig("properties", "name") }).to eq([ "Col des abonnés" ])
    end

    it "rejects a missing, malformed, or nonsensical viewport" do
      get segments_discover_map_path
      expect(response).to have_http_status(:bad_request)

      get segments_discover_map_path(bbox: "6.40,45.06,6.42")
      expect(response).to have_http_status(:bad_request)

      get segments_discover_map_path(bbox: "6.42,45.06,6.40,45.08")
      expect(response).to have_http_status(:bad_request)

      get segments_discover_map_path(bbox: "0,0,999,999")
      expect(response).to have_http_status(:bad_request)
    end

    it "caps the feature count" do
      stub_const("Segments::DiscoveryQuery::MAX_FEATURES", 1)
      create(:segment, user: owner, sport:, visibility: "public", name: "Premier")
      create(:segment, user: owner, sport:, visibility: "public", name: "Second")

      get segments_discover_map_path(bbox:)

      expect(features(response).length).to eq(1)
    end
  end
end
