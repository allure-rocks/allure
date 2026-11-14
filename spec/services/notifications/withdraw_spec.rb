# frozen_string_literal: true

require "rails_helper"

RSpec.describe Notifications::Withdraw do
  let(:recipient) { create(:local_actor) }
  let(:other) { create(:local_actor) }
  let(:remote) { create(:actor) }
  let(:other_remote) { create(:actor) }
  let(:following) { create(:following, follower_actor: remote, followed_actor: recipient) }
  let!(:request_notification) do
    create(:notification, user: recipient.user, actor: remote, subject: following)
  end
  let!(:accepted_notification) do
    create(
      :notification,
      :accepted,
      user: recipient.user,
      actor: remote,
      subject: create(:following, follower_actor: recipient, followed_actor: remote)
    )
  end
  let!(:unrelated_notification) do
    create(
      :notification,
      user: other.user,
      actor: other_remote,
      subject: create(:following, follower_actor: other_remote, followed_actor: other)
    )
  end

  it "removes only the matching relationship entry" do
    described_class.new(user: recipient.user, subject: following, kind: "follow_request").call!

    expect(Notification.where(id: request_notification.id)).not_to exist
    expect(Notification.where(id: accepted_notification.id)).to exist
    expect(Notification.where(id: unrelated_notification.id)).to exist
  end

  it "removes every notification caused by an actor" do
    described_class.new(actor: remote).call!

    expect(Notification.where(id: [ request_notification.id, accepted_notification.id ])).not_to exist
    expect(Notification.where(id: unrelated_notification.id)).to exist
  end
end
