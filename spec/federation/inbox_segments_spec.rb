# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Segment inbox receipt" do
  let(:recipient) { create(:local_actor) }
  let!(:author) do
    create(
      :actor,
      uri: "https://remote.example/users/demo",
      raw: { "followers" => "https://remote.example/users/demo/followers" }
    )
  end

  let!(:follow) { create(:following, :accepted, follower_actor: recipient, followed_actor: author) }

  def item_for(activity, type: "Create")
    @items ||= {}
    @items[[ activity["id"], type ]] ||= create(
      :federation_inbox_item,
      activity_type: type,
      actor_uri: author.uri,
      recipient_actor: recipient,
      activity_uri: activity["id"],
      raw: activity
    )
  end

  def receive_segment(activity = federation_segment_activity)
    Federation::Inbox::Create.new(item: item_for(activity), activity:, now: Time.current).call!
  end

  def delete_segment(activity)
    Federation::Inbox::Delete.new(item: item_for(activity, type: "Delete"), activity:, now: Time.current).call!
  end

  describe "Create" do
    it "persists the course, one entitlement, and pending media descriptors" do
      segment = nil

      expect { segment = receive_segment }
        .to change(RemoteSegment, :count).by(1)
        .and change(RemoteSegmentRecipient, :count).by(1)
        .and change(RemoteSegmentAttachment, :count).by(2)

      expect(segment).to have_attributes(
        name: "Col du Test",
        kind: "segment",
        audience: "public",
        distance: 2_500.0,
        sport_label: "Cycling"
      )
      expect(segment.representation["sport_slug"]).to eq("cycling")
      expect(segment.representation["match_tolerance"]).to eq(25)
      expect(segment.representation).not_to have_key("track")
      expect(segment.recipients.first).to be_active
      expect(segment.attachments.map(&:kind)).to contain_exactly("gpx", "route_image")
      expect(segment.attachments).to all(be_pending)
    end

    it "rejects a course sent to an account that does not follow its author" do
      follow.destroy!

      expect { receive_segment }.to raise_error(Federation::Inbox::Rejected, /does not follow the author/)
      expect(RemoteSegment.count).to eq(0)
    end

    it "is idempotent by object identity" do
      segment = receive_segment

      expect { receive_segment }.not_to change(RemoteSegment, :count)
      expect(receive_segment).to eq(segment)
      expect(RemoteSegmentRecipient.where(remote_segment: segment).count).to eq(1)
    end

    it "never reactivates a withdrawn entitlement" do
      segment = receive_segment
      segment.recipients.first.withdraw!(reason: "unfollow", at: Time.current)

      receive_segment

      expect(segment.recipients.first.reload).to be_withdrawn
    end

    it "stores a followers-only course while restricted federation is on" do
      activity = federation_segment_activity
      activity["object"]["to"] = [ "#{author.uri}/followers" ]
      activity["to"] = [ "#{author.uri}/followers" ]
      allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(true)

      expect { receive_segment(activity) }.to change(RemoteSegment, :count).by(1)
      expect(RemoteSegment.last.audience).to eq("followers")
    end

    it "rejects a followers-only course while restricted federation is off" do
      activity = federation_segment_activity
      activity["object"]["to"] = [ "#{author.uri}/followers" ]
      activity["to"] = [ "#{author.uri}/followers" ]
      allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(false)

      expect { receive_segment(activity) }.to raise_error(Federation::Inbox::Rejected, /restricted audience/)
    end

    it "rejects a course without a GPX attachment" do
      activity = federation_segment_activity
      activity["object"]["attachment"] = []

      expect { receive_segment(activity) }.to raise_error(Federation::Inbox::Rejected, /no GPX attachment/)
      expect(RemoteSegment.count).to be_zero
    end
  end

  describe "Delete" do
    it "tombstones a course never seen locally" do
      segment = delete_segment(federation_segment_delete_activity)

      expect(segment).to be_deleted
      expect(segment.name).to eq("")
      expect(segment.representation).to eq("redacted" => true)
      expect(segment.attachments).to be_empty
    end

    it "withdraws entitlements, purges media, and redacts an existing course" do
      segment = receive_segment

      delete_segment(federation_segment_delete_activity)

      expect(segment.reload).to be_deleted
      expect(segment.recipients).to all(be_withdrawn)
      expect(segment.attachments).to all(be_purged)
      expect(segment).to be_location_data_purged
      expect(segment.representation["redacted"]).to be(true)
    end

    it "tombstones the author and purges every course it delivered" do
      segment = receive_segment

      delete_segment(federation_segment_delete_activity(object: author.uri))

      expect(author.reload).to be_tombstoned
      expect(segment.reload.recipients).to all(be_withdrawn)
      expect(segment.attachments).to all(be_purged)
      expect(segment).to be_location_data_purged
    end
  end

  it "enqueues the segment media fetch after the receipt commits" do
    activity = federation_segment_activity
    item = item_for(activity)
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    Federation::ProcessInboxItemJob.perform_now(item)

    expect(Federation::FetchRemoteSegmentAttachmentJob).to have_been_enqueued.at_least(:once)
    expect(Federation::FetchRemoteNoteAttachmentJob).not_to have_been_enqueued
  end
end
