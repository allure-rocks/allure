# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Remote notes" do
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
  let(:title) { "Morning hike" }
  let(:representation) do
    {
      "title" => title,
      "description" => "A short description",
      "sport_label" => "Hiking",
      "started_at" => "2026-08-26T12:00:00Z",
      "metrics" => { "distance" => 1234.5, "duration" => 600.0 },
      "track" => {
        "type" => "FeatureCollection",
        "features" => [
          { "type" => "Feature",
            "geometry" => { "type" => "LineString", "coordinates" => [ [ 12.345678, 45.987654 ], [ 12.4, 45.9 ] ] },
            "properties" => { "segment_index" => 0 } }
        ]
      },
      "chart" => [ { "distance" => 0.0, "elapsed_time" => nil, "elevation" => 100.0 } ]
    }
  end
  let(:note) do
    create(
      :remote_note,
      actor: author,
      sport_label: "Hiking",
      content_html: "Morning hike<br>A short description",
      metrics: representation["metrics"],
      representation:
    )
  end

  def cache_attachment(kind:, body:, content_type:)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(body), filename: "media-#{kind}", content_type:, identify: false
    )
    create(:remote_note_attachment, remote_note: note, kind:, status: "cached", blob:)
  end

  it "requires a session" do
    get remote_note_path(note)

    expect(response).to redirect_to(new_session_path)
  end

  it "renders a public note to any signed-in account" do
    cache_attachment(kind: "gpx", body: "<gpx/>", content_type: "application/xml+gpx")
    sign_in_as(viewer)

    get remote_note_path(note)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Morning hike", "A short description", "Demo Remote")
    expect(response.body).to include(remote_note_track_path(note), remote_note_gpx_path(note))
  end

  it "shows published record markers to a signed-in viewer" do
    marked = create(:remote_note, actor: author, sport_label: "Hiking",
                                  representation: representation.merge(
                                    "record_types" => %w[FD HA], "record_distances" => %w[km5]
                                  ))
    sign_in_as(viewer)

    get remote_note_path(marked)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("workouts.show.records.badge_short"))
    expect(response.body).to include(I18n.t("records.types.fd"), I18n.t("records.distances.km5"))
    expect(response.body).to include(I18n.t("medals.record", record: I18n.t("records.types.fd")))
  end

  it "shows the shared recording device to a signed-in viewer" do
    with_device = create(:remote_note, actor: author, sport_label: "Hiking",
                                       representation: representation.merge("device" => "Garmin Edge 530"))
    sign_in_as(viewer)

    get remote_note_path(with_device)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Garmin Edge 530")
  end

  it "shows the commute badge only when the flag is shared" do
    commuting = create(:remote_note, actor: author, sport_label: "Hiking",
                                     representation: representation.merge("commute" => true))
    sign_in_as(viewer)

    get remote_note_path(commuting)
    expect(response.body).to include("ti-briefcase", I18n.t("workouts.commute.badge"))

    get remote_note_path(note)
    expect(response.body).not_to include("ti-briefcase")
  end

  it "leaks no origin URL, storage URL, or coordinates into the HTML" do
    cache_attachment(kind: "gpx", body: "<gpx/>", content_type: "application/xml+gpx")
    sign_in_as(viewer)

    get remote_note_path(note)

    expect(response.body).not_to include(author.uri)
    expect(response.body).not_to include("active_storage", "/rails/")
    expect(response.body).not_to include("12.345678", "45.987654")
  end

  it "sanitizes remote content at render time" do
    RemoteNote.where(id: note.id).update_all(
      content_html: "<script>alert(1)</script><img src=x onerror=alert(2)><strong>Hi</strong>"
    )
    sign_in_as(viewer)

    get remote_note_path(note)

    expect(response.body).not_to include("<script>alert", "<img", "onerror")
    expect(response.body).to include("<strong>Hi</strong>")
  end

  it "requires an entitlement for a followers note" do
    note.update!(audience: "followers")
    sign_in_as(viewer)

    get remote_note_path(note)
    expect(response).to have_http_status(:not_found)

    actor = Federation::ActorProvisioner.new(user: viewer).call!
    create(:remote_note_recipient, remote_note: note, recipient_actor: actor)

    get remote_note_path(note)
    expect(response).to have_http_status(:ok)
  end

  it "shows a tombstone to former recipients and 404s everyone else" do
    actor = Federation::ActorProvisioner.new(user: viewer).call!
    recipient = create(:remote_note_recipient, remote_note: note, recipient_actor: actor)
    note.mark_deleted!
    recipient.withdraw!(reason: "deleted")

    sign_in_as(viewer)
    get remote_note_path(note)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("remote_notes.deleted.title"))

    other = create(:user)
    sign_in_as(other)
    get remote_note_path(note)
    expect(response).to have_http_status(:not_found)
  end

  it "shows an author-unavailable state without linking a tombstoned account" do
    author.tombstone!
    sign_in_as(viewer)

    get remote_note_path(note)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(ERB::Util.html_escape(I18n.t("remote_notes.author_unavailable")))
    expect(response.body).not_to include(remote_profile_path(author.acct))
  end

  it "shows a pending media state inside a refresh frame" do
    create(:remote_note_attachment, remote_note: note, kind: "gpx", status: "pending")
    sign_in_as(viewer)

    get remote_note_path(note)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("remote_notes.media.pending"))
    expect(response.body).to include('data-controller="refresh"')
  end
end
