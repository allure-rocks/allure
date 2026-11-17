# frozen_string_literal: true

require "rails_helper"

# docs/dev/PUSH.md: which inbox writes reach the devices.
RSpec.describe "Push enqueueing from the notification producers" do
  include ActiveJob::TestHelper

  let(:owner) { create(:user) }
  let(:session) { owner.sessions.create!(auth_method: "password") }
  let(:workout) { create(:workout, user: owner) }

  around { |example| with_push_env { example.run } }

  before { create_push_subscription(session:) }

  def react(actor: create(:actor), kind: "like", alert: true)
    reaction = create(:reaction, actor:, workout:, kind:)
    Notifications::Create.new(user: owner, kind: "reaction", actor:, subject: reaction, alert:).call!
    reaction
  end

  def digest = Notification.find_by(user: owner, kind: "reaction", subject: workout)

  def follow_request(user: owner)
    requester = create(:local_actor)
    following = create(:following, follower_actor: requester, followed_actor: create(:local_actor, user:))
    Notifications::Create.new(user:, kind: "follow_request", actor: requester, subject: following)
  end

  it "pushes a new notification once, and not its idempotent repeat" do
    producer = follow_request

    expect { producer.call! }.to have_enqueued_job(Notifications::PushJob).exactly(:once)
    expect(Notifications::PushJob).to have_been_enqueued.with(Notification.last.id)
    expect { producer.call! }.not_to have_enqueued_job(Notifications::PushJob)
  end

  it "waits for the producer's transaction and pushes nothing it rolled back" do
    producer = follow_request

    expect do
      ActiveRecord::Base.transaction do
        producer.call!
        raise ActiveRecord::Rollback
      end
    end.not_to have_enqueued_job(Notifications::PushJob)
  end

  it "pushes a new reaction digest and a digest turned unread again" do
    expect { react }.to have_enqueued_job(Notifications::PushJob).exactly(:once)
    expect(Notifications::PushJob).to have_been_enqueued.with(digest.id)

    digest.update!(read_at: 1.hour.ago)
    expect { react }.to have_enqueued_job(Notifications::PushJob).with(digest.id)
  end

  it "pushes nothing for a silent type switch or a withdrawal" do
    actor = create(:actor)
    first = react(actor:, kind: "beer")
    first.undo!
    reaction = create(:reaction, actor:, workout:, kind: "coffee")

    expect do
      Notifications::Create.new(user: owner, kind: "reaction", actor:, subject: reaction, alert: false).call!
    end.not_to have_enqueued_job(Notifications::PushJob)
    expect { Notifications::Withdraw.new(subject: reaction).call! }.not_to have_enqueued_job(Notifications::PushJob)
  end

  it "pushes nothing for an account without a subscription" do
    expect { follow_request(user: create(:user)).call! }.not_to have_enqueued_job(Notifications::PushJob)
  end

  it "pushes nothing while push is unconfigured" do
    with_push_env(push_env("VAPID_PUBLIC_KEY" => nil)) do
      expect { follow_request.call! }.not_to have_enqueued_job(Notifications::PushJob)
    end
  end

  it "pushes nothing for a kind the account turned off" do
    owner.update!(notify_follow_requests: false)

    expect { follow_request.call! }.not_to have_enqueued_job(Notifications::PushJob)
  end
end
