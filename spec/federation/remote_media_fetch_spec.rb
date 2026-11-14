# frozen_string_literal: true

require "rails_helper"

RSpec.describe Federation::RemoteMedia::Fetch do
  let(:author) { create(:actor, uri: "https://remote.example/users/demo") }
  let(:recipient) { create(:local_actor) }
  let(:note) { create(:remote_note, actor: author, source_domain: "remote.example") }
  let!(:entitlement) { create(:remote_note_recipient, remote_note: note, recipient_actor: recipient) }
  let(:attachment) do
    create(:remote_note_attachment, remote_note: note, kind: "gpx", remote_url: "https://remote.example/track.gpx")
  end
  let(:client) { instance_double(Federation::Transport::Client) }
  let(:gpx_body) { File.read(Rails.root.join("spec/fixtures/gpx/multi_segment.gpx")) }

  def response(status: 200, body: gpx_body)
    Federation::Transport::Client::Response.new(
      status, {}, body, URI("https://remote.example/track.gpx")
    )
  end

  before do
    allow(client).to receive(:get).and_return(response(status: 200))
  end

  def fetch
    described_class.new(attachment:, client:).call!
  end

  it "caches a verified GPX and writes the remote geometry" do
    expect { fetch }.to change(ActiveStorage::Blob, :count).by(1)

    expect(attachment.reload).to be_cached
    expect(attachment.content_digest).to be_present
    expect(attachment.byte_size).to eq(gpx_body.bytesize)

    representation = note.reload.representation
    expect(representation.dig("track", "features").length).to eq(2)
    expect(representation.dig("track", "features", 0, "properties", "segment_index")).to eq(0)
    expect(representation.fetch("chart")).to be_an(Array)
    expect(note.route_metadata.fetch("segments_count")).to eq(2)
    expect(note.route_metadata.fetch("bounds").length).to eq(4)
    expect(Workout.count).to eq(0)
    expect(TrackSegment.count).to eq(0)
  end

  it "caches a verified route image without deriving geometry" do
    attachment.update!(kind: "route_image", remote_url: "https://remote.example/route.png")
    image = Vips::Image.black(64, 64).write_to_buffer(".png")
    allow(client).to receive(:get).and_return(response(body: image))

    fetch

    expect(attachment.reload).to be_cached
    expect(attachment.blob.content_type).to eq("image/png")
    expect(note.reload.representation).not_to have_key("track")
  end

  it "marks a wrong declared content type as unavailable" do
    allow(client).to receive(:get).and_return(response(body: "definitely not gpx"))

    fetch

    expect(attachment.reload.status).to eq("unavailable")
    expect(ActiveStorage::Blob.count).to eq(0)
  end

  it "does not fetch from a blocked domain" do
    create(:federation_domain_block, domain: "remote.example")

    fetch

    expect(attachment.reload).to be_unavailable
    expect(client).not_to have_received(:get)
  end

  it "does not fetch a note from a blocked actor" do
    create(:federation_actor_block, actor_uri: author.uri)

    fetch

    expect(attachment.reload).to be_unavailable
    expect(client).not_to have_received(:get)
  end

  it "does not sign a fetch towards another authority" do
    attachment.update!(remote_url: "https://victim.example/api/v1/trail/xyz/media/gpx")

    fetch

    expect(attachment.reload).to be_unavailable
    expect(attachment.last_error).to match(/attachment authority/)
    expect(client).not_to have_received(:get)
  end

  it "does not sign a fetch towards another port of the source domain" do
    attachment.update!(remote_url: "https://remote.example:8443/track.gpx")

    fetch

    expect(attachment.reload).to be_unavailable
    expect(client).not_to have_received(:get)
  end

  it "does not fetch without an active recipient" do
    entitlement.withdraw!(reason: "unfollow")

    fetch

    expect(attachment.reload).to be_unavailable
    expect(client).not_to have_received(:get)
  end

  it "does not fetch for a deleted note" do
    note.mark_deleted!

    fetch

    expect(attachment.reload).to be_unavailable
    expect(client).not_to have_received(:get)
  end

  it "retries transient failures and stops at the attempt cap" do
    allow(client).to receive(:get).and_return(response(status: 500))

    fetch

    expect(attachment.reload.status).to eq("failed")
    expect(attachment.next_attempt_at).to be_present
    expect(Federation::FetchRemoteNoteAttachmentJob).to have_been_enqueued

    attachment.update!(attempts: described_class::MAX_ATTEMPTS - 1)
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    fetch

    expect(attachment.reload.status).to eq("failed")
    expect(attachment.next_attempt_at).to be_nil
  end

  it "marks a 410 as unavailable" do
    allow(client).to receive(:get).and_return(response(status: 410))

    fetch

    expect(attachment.reload).to be_unavailable
  end

  it "fails terminally on a byte-limit breach" do
    allow(client).to receive(:get).and_raise(Federation::Transport::Client::ResponseTooLarge)

    fetch

    expect(attachment.reload.status).to eq("failed")
    expect(attachment.next_attempt_at).to be_nil
  end

  it "marks an unsafe URL as unavailable" do
    allow(client).to receive(:get).and_raise(Federation::Transport::SsrfGuard::UnsafeUri)

    fetch

    expect(attachment.reload).to be_unavailable
  end

  it "is idempotent once cached" do
    fetch
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    expect { fetch }.not_to change(ActiveStorage::Blob, :count)
    expect(client).to have_received(:get).once
  end
end
