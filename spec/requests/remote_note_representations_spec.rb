# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Remote note representations" do
  let(:viewer) { create(:user) }
  let(:representation) do
    {
      "title" => "Morning hike",
      "sport_label" => "Hiking",
      "started_at" => "2026-08-26T12:00:00Z",
      "metrics" => {},
      "track" => {
        "type" => "FeatureCollection",
        "features" => [
          { "type" => "Feature",
            "geometry" => { "type" => "LineString", "coordinates" => [ [ 6.4, 45.0 ], [ 6.5, 45.1 ] ] },
            "properties" => { "segment_index" => 0 } }
        ]
      },
      "chart" => [ { "distance" => 0.0, "elapsed_time" => nil, "elevation" => 100.0 } ]
    }
  end
  let(:note) { create(:remote_note, representation:) }

  it "serves the parsed track and chart to a signed-in viewer" do
    sign_in_as(viewer)

    get remote_note_track_path(note)
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/geo+json")
    expect(response.headers["Cache-Control"]).to eq("private, no-store")
    expect(JSON.parse(response.body).fetch("type")).to eq("FeatureCollection")

    get remote_note_chart_path(note)
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body).fetch("points").length).to eq(1)
    expect(response.headers["Cache-Control"]).to eq("private, no-store")
  end

  it "requires a session" do
    get remote_note_track_path(note)

    expect(response).to redirect_to(new_session_path)
  end

  it "404s a representation that is not present yet" do
    RemoteNote.where(id: note.id).update_all(
      representation: { "title" => "Empty", "sport_label" => "Hiking", "metrics" => {} }
    )
    sign_in_as(viewer)

    get remote_note_track_path(note)
    expect(response).to have_http_status(:not_found)

    get remote_note_chart_path(note)
    expect(response).to have_http_status(:not_found)
  end

  it "404s a followers note without an entitlement" do
    note.update!(audience: "followers")
    sign_in_as(viewer)

    get remote_note_track_path(note)
    expect(response).to have_http_status(:not_found)

    actor = Federation::ActorProvisioner.new(user: viewer).call!
    create(:remote_note_recipient, remote_note: note, recipient_actor: actor)

    get remote_note_track_path(note)
    expect(response).to have_http_status(:ok)
  end
end
