# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Remote note media" do
  let(:note) { create(:remote_note) }
  let(:viewer) { create(:user) }

  def cached_attachment(kind:, body:, content_type:, theme: "light")
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(body), filename: "media-#{kind}-#{theme}", content_type:, identify: false
    )
    create(:remote_note_attachment, remote_note: note, kind:, theme:, status: "cached", blob:)
  end

  before do
    cached_attachment(kind: "gpx", body: "<gpx/>", content_type: "application/xml+gpx")
    cached_attachment(kind: "route_image", body: "\x89PNG\r\n\x1a\n".b, content_type: "image/png")
  end

  it "requires a session" do
    get remote_note_gpx_path(note)

    expect(response).to redirect_to(new_session_path)
  end

  it "serves cached GPX and route image bytes to a signed-in member" do
    sign_in_as(viewer)

    get remote_note_gpx_path(note)
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/xml+gpx")
    expect(response.headers["Cache-Control"]).to eq("private, no-store")

    get remote_note_route_image_path(note)
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("image/png")
    expect(response.headers["Cache-Control"]).to eq("private, no-store")
  end

  it "serves the requested image variant and falls back to the cached one" do
    sign_in_as(viewer)

    get remote_note_route_image_path(note, theme: "dark")
    expect(response).to have_http_status(:ok)
    expect(response.body).to eq("\x89PNG\r\n\x1a\n".b)

    cached_attachment(kind: "route_image", body: "\x89PNG\r\n\x1a\ndark".b,
                      content_type: "image/png", theme: "dark")

    get remote_note_route_image_path(note, theme: "dark")
    expect(response).to have_http_status(:ok)
    expect(response.body).to end_with("dark".b)
  end

  it "404s a pending or deleted attachment" do
    note.attachments.update_all(status: "purged", blob_id: nil)
    sign_in_as(viewer)

    get remote_note_gpx_path(note)

    expect(response).to have_http_status(:not_found)
  end

  it "404s a deleted note" do
    note.mark_deleted!
    sign_in_as(viewer)

    get remote_note_gpx_path(note)

    expect(response).to have_http_status(:not_found)
  end

  it "requires an entitlement for a followers note" do
    note.update_column(:audience, "followers")
    sign_in_as(viewer)

    get remote_note_gpx_path(note)
    expect(response).to have_http_status(:not_found)

    actor = Federation::ActorProvisioner.new(user: viewer).call!
    create(:remote_note_recipient, remote_note: note, recipient_actor: actor)

    get remote_note_gpx_path(note)
    expect(response).to have_http_status(:ok)
  end
end
