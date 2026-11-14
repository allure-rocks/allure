# frozen_string_literal: true

require "rails_helper"

RSpec.describe Notifications::Create do
  let(:recipient) { create(:local_actor) }
  let(:requester) { create(:local_actor) }
  let(:following) { create(:following, follower_actor: requester, followed_actor: recipient) }

  def create_notification(**options)
    described_class.new(
      user: recipient.user,
      kind: "follow_request",
      actor: requester,
      subject: following,
      **options
    ).call!
  end

  it "creates one unread notification for the recipient" do
    expect { create_notification }.to change(Notification, :count).by(1)

    notification = Notification.last
    expect(notification.user).to eq(recipient.user)
    expect(notification.actor).to eq(requester)
    expect(notification.subject).to eq(following)
    expect(notification).not_to be_read
  end

  it "is idempotent for the same recipient, kind, and subject" do
    create_notification

    expect { create_notification }.not_to change(Notification, :count)
  end

  it "finds a repeated request's row without attempting an insert the unique index refuses" do
    first = create_notification
    expect(Notification).not_to receive(:create_or_find_by!)

    expect(create_notification).to eq(first)
  end

  it "still settles a race between two first calls on the unique index" do
    first = create_notification
    allow(Notification).to receive(:find_by).and_return(nil)

    expect { expect(create_notification).to eq(first) }.not_to change(Notification, :count)
  end

  it "never notifies an account about its own action" do
    expect { create_notification(user: requester.user, actor: requester) }
      .not_to change(Notification, :count)
  end

  it "respects the recipient's preference" do
    recipient.user.update!(notify_follow_requests: false)

    expect { create_notification }.not_to change(Notification, :count)
  end

  it "does not notify a suspended account" do
    recipient.user.update!(suspended_at: Time.current)

    expect { create_notification }.not_to change(Notification, :count)
  end

  it "caps the inbox by pruning the oldest rows" do
    oldest = create(
      :notification,
      :accepted,
      user: recipient.user,
      subject: create(:following, follower_actor: create(:actor), followed_actor: create(:actor)),
      created_at: 2.days.ago
    )
    survivor = (Notification::MAX_PER_USER - 1).times.map do |index|
      create(
        :notification,
        user: recipient.user,
        subject: create(:following, follower_actor: create(:actor), followed_actor: create(:actor)),
        created_at: index.minutes.ago
      )
    end.last

    create_notification

    expect(Notification.where(user: recipient.user).count).to eq(Notification::MAX_PER_USER)
    expect(Notification.where(id: oldest.id)).not_to exist
    expect(Notification.where(id: survivor.id)).to exist
  end

  it "never prunes an unread notification awaiting a decision" do
    pending_request = create(
      :notification,
      user: recipient.user,
      subject: create(:following, follower_actor: create(:actor), followed_actor: create(:actor)),
      created_at: 3.days.ago
    )
    read_request = create(
      :notification,
      user: recipient.user,
      subject: create(:following, follower_actor: create(:actor), followed_actor: create(:actor)),
      created_at: 2.days.ago,
      read_at: 1.day.ago
    )
    (Notification::MAX_PER_USER - 1).times do |index|
      create(:notification, :accepted, user: recipient.user,
                                       subject: create(:following, follower_actor: create(:actor), followed_actor: create(:actor)),
                                       created_at: index.minutes.ago)
    end

    create_notification

    expect(Notification.where(id: pending_request.id)).to exist
    expect(Notification.where(id: read_request.id)).not_to exist
  end
end
