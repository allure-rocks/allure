# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Remote segments" do
  let(:author) do
    create(
      :actor,
      uri: "https://remote.example/users/demo",
      handle: "demo@remote.example",
      acct: "demo@remote.example",
      display_name: "Demo Remote"
    )
  end
  let(:viewer) { create(:user) }
  let(:representation) do
    {
      "name" => "Col du Test",
      "description" => "Le versant nord",
      "sport_slug" => "cycling",
      "kind" => "segment",
      "distance" => 2500.0,
      "ascent" => 180.0,
      "match_tolerance" => 25,
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

  before { catalog_sport("cycling") }

  def sign_in_as(user)
    post session_path, params: { email_address: user.email_address, password: "allure-test-password" }
  end

  def cache_attachment(kind:, body:, content_type:)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(body), filename: "media-#{kind}", content_type:, identify: false
    )
    create(:remote_segment_attachment, remote_segment: segment, kind:, status: "cached", blob:)
  end

  it "requires a session" do
    get remote_segment_path(segment)

    expect(response).to redirect_to(new_session_path)
  end

  it "renders a public course to any signed-in account" do
    cache_attachment(kind: "gpx", body: "<gpx/>", content_type: "application/xml+gpx")
    sign_in_as(viewer)

    get remote_segment_path(segment)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Col du Test", "Demo Remote", remote_segment_track_path(segment))
    expect(response.body).to include(I18n.t("remote_segments.copy.action"))
  end

  it "does not leak remote URLs, storage paths, or coordinates" do
    cache_attachment(kind: "gpx", body: "<gpx/>", content_type: "application/xml+gpx")
    sign_in_as(viewer)

    get remote_segment_path(segment)

    expect(response.body).not_to include("active_storage", "/rails/")
    expect(response.body).not_to include("6.4074", "45.071")
  end

  it "gates a followers-only course on an active entitlement" do
    segment.update_columns(audience: "followers")
    sign_in_as(viewer)

    get remote_segment_path(segment)
    expect(response).to have_http_status(:not_found)

    create(
      :remote_segment_recipient,
      remote_segment: segment,
      recipient_actor: Federation::ActorProvisioner.new(user: viewer).call!
    )

    get remote_segment_path(segment)
    expect(response).to have_http_status(:ok)
  end

  it "renders a pending media refresh frame" do
    create(:remote_segment_attachment, remote_segment: segment, kind: "gpx", status: "pending")
    sign_in_as(viewer)

    get remote_segment_path(segment)

    expect(response.body).to include(I18n.t("remote_segments.media.pending"))
    expect(response.body).to include('data-controller="refresh"')
  end

  it "renders a tombstone for former recipients only" do
    recipient = create(
      :remote_segment_recipient,
      remote_segment: segment,
      recipient_actor: Federation::ActorProvisioner.new(user: viewer).call!
    )
    segment.mark_deleted!
    recipient.withdraw!(reason: "deleted")
    sign_in_as(viewer)

    get remote_segment_path(segment)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("remote_segments.deleted.title"))

    stranger = create(:user)
    sign_in_as(stranger)
    get remote_segment_path(segment)
    expect(response).to have_http_status(:not_found)
  end

  describe "copying" do
    before { cache_attachment(kind: "gpx", body: "<gpx/>", content_type: "application/xml+gpx") }

    it "creates a private local segment and redirects to it" do
      sign_in_as(viewer)

      expect { post remote_segment_import_path(segment) }
        .to change(Segment, :count).by(1)

      copy = Segment.order(:id).last
      expect(response).to redirect_to(segment_path(copy))
      expect(copy).to have_attributes(
        user: viewer,
        remote_segment: segment,
        visibility: "private"
      )
    end

    it "is idempotent and never creates a second copy" do
      sign_in_as(viewer)
      post remote_segment_import_path(segment)
      copy = Segment.order(:id).last

      expect { post remote_segment_import_path(segment) }.not_to change(Segment, :count)
      expect(Segment.order(:id).last).to eq(copy)
    end

    it "refuses a non-entitled view of a followers-only course" do
      segment.update_columns(audience: "followers")
      sign_in_as(viewer)

      post remote_segment_import_path(segment)

      expect(response).to have_http_status(:not_found)
      expect(Segment.count).to be_zero
    end

    it "reports a copy failure without creating a segment" do
      segment.attachments.update_all(status: "pending")
      sign_in_as(viewer)

      post remote_segment_import_path(segment)

      expect(response).to redirect_to(remote_segment_path(segment))
      expect(flash[:alert]).to eq(I18n.t("segments.remote_copy.errors.pending_media"))
      expect(Segment.count).to be_zero
    end
  end
end
