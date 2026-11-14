# frozen_string_literal: true

require "rails_helper"

RSpec.describe Federation::FollowDecision do
  let(:recipient) { create(:local_actor) }
  let(:remote) { create(:actor, uri: "https://remote.example/users/demo") }
  let(:following) do
    create(
      :following,
      follower_actor: remote,
      followed_actor: recipient,
      uri: "https://remote.example/activities/follow-1"
    )
  end

  before { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }

  it "accepts a pending request and emits one Accept" do
    expect {
      described_class.new(following:, decision: "accept").call!
    }.to change { FederationOutboxEvent.where(activity_type: "Accept").count }.by(1)

    expect(following.reload).to be_accepted
    expect(Federation::ExpandOutboxEventJob).to have_been_enqueued
  end

  it "rejects a pending request and emits one Reject" do
    described_class.new(following:, decision: "reject").call!

    expect(following.reload).to be_rejected
    event = FederationOutboxEvent.find_by!(activity_type: "Reject")
    expect(event.payload.fetch("object")).to eq(following.uri)
    expect(event.audience.fetch("to")).to eq([ remote.uri ])
  end

  it "withdraws the recipient's pending request notification" do
    notification = create(:notification, user: recipient.user, actor: remote, subject: following)

    described_class.new(following:, decision: "accept").call!

    expect(Notification.where(id: notification.id)).not_to exist
  end

  it "withdraws the pending request notification on reject" do
    notification = create(:notification, user: recipient.user, actor: remote, subject: following)

    described_class.new(following:, decision: "reject").call!

    expect(Notification.where(id: notification.id)).not_to exist
  end

  it "refuses to decide an already accepted request" do
    following.accept!

    expect { described_class.new(following:, decision: "accept").call! }
      .to raise_error(described_class::InvalidDecision)
  end

  it "refuses an unknown decision" do
    expect { described_class.new(following:, decision: "maybe").call! }
      .to raise_error(described_class::InvalidDecision)
  end

  it "refuses to accept a blocked follower" do
    create(:federation_actor_block, actor_uri: remote.uri)

    expect { described_class.new(following:, decision: "accept").call! }
      .to raise_error(described_class::InvalidDecision)
    expect(following.reload).to be_pending
  end

  describe "a local follower" do
    let(:follower) { create(:local_actor) }
    let(:local_following) do
      create(:following, follower_actor: follower, followed_actor: recipient)
    end

    it "accepts without emitting any federation event" do
      expect {
        described_class.new(following: local_following, decision: "accept").call!
      }.not_to change(FederationOutboxEvent, :count)

      expect(local_following.reload).to be_accepted
      expect(Federation::ExpandOutboxEventJob).not_to have_been_enqueued
    end

    it "rejects without emitting any federation event" do
      expect {
        described_class.new(following: local_following, decision: "reject").call!
      }.not_to change(FederationOutboxEvent, :count)

      expect(local_following.reload).to be_rejected
    end

    it "notifies the local follower when the request is accepted" do
      described_class.new(following: local_following, decision: "accept").call!

      notification = Notification.find_by!(
        user: follower.user, kind: "follow_accepted", subject: local_following
      )
      expect(notification.actor).to eq(recipient)
    end

    it "does not notify the local follower when the request is rejected" do
      described_class.new(following: local_following, decision: "reject").call!

      expect(Notification.where(kind: "follow_accepted")).to be_empty
    end

    it "withdraws the target's pending request notification" do
      notification = create(:notification, user: recipient.user, actor: follower, subject: local_following)

      described_class.new(following: local_following, decision: "accept").call!

      expect(Notification.where(id: notification.id)).not_to exist
    end
  end
end
