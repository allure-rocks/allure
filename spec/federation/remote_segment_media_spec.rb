# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Remote segment media" do
  let(:author) { create(:actor, uri: "https://remote.example/users/demo") }
  let(:recipient) { create(:local_actor) }
  let(:segment) { create(:remote_segment, actor: author, source_domain: "remote.example") }
  let!(:entitlement) { create(:remote_segment_recipient, remote_segment: segment, recipient_actor: recipient) }
  let(:gpx_body) { File.read(Rails.root.join("spec/fixtures/gpx/multi_segment.gpx")) }
  let(:client) { instance_double(Federation::Transport::Client) }

  def response(status: 200, body: gpx_body)
    Federation::Transport::Client::Response.new(
      status, {}, body, URI("https://remote.example/segment.gpx")
    )
  end

  def gpx_attachment
    create(:remote_segment_attachment, remote_segment: segment, kind: "gpx",
                                       remote_url: "https://remote.example/segment.gpx")
  end

  describe Federation::RemoteMedia::Fetch do
    it "caches the course geometry without a chart" do
      attachment = gpx_attachment
      allow(client).to receive(:get).and_return(response)

      expect { described_class.new(attachment:, client:).call! }
        .to change(ActiveStorage::Blob, :count).by(1)

      expect(attachment.reload).to be_cached
      representation = segment.reload.representation
      expect(representation.dig("track", "features", 0, "properties", "segment_index")).to eq(0)
      expect(representation).not_to have_key("chart")
      expect(segment.route_metadata.fetch("segments_count")).to eq(2)
      expect(segment.route_metadata.fetch("bounds").length).to eq(4)
      expect(attachment.blob.filename.to_s).to eq("remote-segment-#{segment.id}.gpx")
    end

    it "is unavailable without an active entitlement" do
      attachment = gpx_attachment
      entitlement.withdraw!(reason: "unfollow", at: Time.current)
      allow(client).to receive(:get)

      described_class.new(attachment:, client:).call!

      expect(attachment.reload).to be_unavailable
      expect(client).not_to have_received(:get)
    end
  end

  describe Federation::RemoteMedia::Purge do
    it "retains a public course's media on the last withdrawal" do
      attachment = gpx_attachment
      attachment.update!(status: "cached", blob_id: create_blob("gpx").id)
      entitlement.withdraw!(reason: "unfollow", at: Time.current)

      described_class.new(owner: segment).call!

      expect(attachment.reload).to be_cached
      expect(segment.reload).not_to be_location_data_purged
    end

    it "purges a followers-only course when the last entitlement goes" do
      segment.update_columns(audience: "followers")
      attachment = gpx_attachment
      attachment.update!(status: "cached", blob_id: create_blob("gpx").id)
      entitlement.withdraw!(reason: "unfollow", at: Time.current)

      described_class.new(owner: segment).call!

      expect(attachment.reload).to be_purged
      expect(segment.reload).to be_location_data_purged
    end
  end

  describe Federation::RemoteMedia::Recovery do
    it "re-enqueues due segment descriptors through their own job" do
      attachment = gpx_attachment
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear

      described_class.new.call

      expect(Federation::FetchRemoteSegmentAttachmentJob)
        .to have_been_enqueued.with(attachment.id, segment.source_domain)
    end

    it "releases a stale segment fetch lease" do
      attachment = gpx_attachment
      attachment.update!(status: "fetching")
      attachment.update_column(:updated_at, 20.minutes.ago)

      result = described_class.new.call

      expect(result.released).to eq(1)
      expect(attachment.reload).to be_failed
    end
  end

  describe Federation::RemoteMedia::Retry do
    it "resets a failed segment descriptor and re-enqueues its job" do
      attachment = gpx_attachment
      attachment.update!(status: "failed", attempts: 5)
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear

      described_class.new.call

      expect(attachment.reload).to be_pending
      expect(attachment.attempts).to be_zero
      expect(Federation::FetchRemoteSegmentAttachmentJob)
        .to have_been_enqueued.with(attachment.id, segment.source_domain)
    end
  end

  def create_blob(_kind)
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("gpx"),
      filename: "segment.gpx",
      content_type: "application/gpx+xml"
    )
  end
end
