# frozen_string_literal: true

require "rails_helper"

RSpec.describe Notifications::ReactionDigest do
  let(:owner) { create(:user) }
  let(:workout) { create(:workout, user: owner) }

  def react(actor: create(:actor), kind: "like")
    reaction = create(:reaction, actor:, workout:, kind:)
    Notifications::Create.new(user: owner, kind: "reaction", actor:, subject: reaction).call!
    reaction
  end

  def digest = Notification.find_by(user: owner, kind: "reaction", subject: workout)

  it "keeps one notification per workout, naming the newest account and counting every reaction" do
    react(kind: "beer")
    react(kind: "beer")
    newest = create(:actor)
    expect { react(actor: newest, kind: "coffee") }.not_to change(Notification, :count)

    expect(Notification.where(user: owner, kind: "reaction").count).to eq(1)
    expect(digest.actor).to eq(newest)
    expect(digest.payload).to eq("count" => 3, "kinds" => { "beer" => 2, "coffee" => 1 })
  end

  it "finds an existing digest without attempting an insert the unique index refuses" do
    react
    expect(Notification).not_to receive(:create_or_find_by!)

    react

    expect(digest.payload["count"]).to eq(2)
  end

  it "keeps 60 reactions in a single entry" do
    60.times { react }

    expect(Notification.where(user: owner).count).to eq(1)
    expect(digest.payload["count"]).to eq(60)
  end

  it "turns unread again and moves to the top on a new reaction" do
    react
    digest.update!(read_at: 1.hour.ago, created_at: 2.days.ago)

    react

    expect(digest).not_to be_read
    expect(digest.created_at).to be > 1.minute.ago
  end

  it "recounts silently when an account only switches its type" do
    actor = create(:actor)
    old = react(actor:, kind: "beer")
    digest.update!(read_at: 1.hour.ago, created_at: 2.days.ago)
    old.undo!
    reaction = create(:reaction, actor:, workout:, kind: "coffee")

    Notifications::Create.new(user: owner, kind: "reaction", actor:, subject: reaction, alert: false).call!

    expect(digest).to be_read
    expect(digest.created_at).to be < 1.day.ago
    expect(digest.payload).to eq("count" => 1, "kinds" => { "coffee" => 1 })
  end

  it "recounts on a withdrawn reaction and goes away with the last one" do
    first = react
    second = react
    digest.update!(read_at: 1.hour.ago)

    second.undo!
    Notifications::Withdraw.new(user: owner, kind: "reaction", subject: second).call!

    expect(digest.payload["count"]).to eq(1)
    expect(digest.actor).to eq(first.actor)
    expect(digest).to be_read

    first.undo!
    Notifications::Withdraw.new(user: owner, kind: "reaction", subject: first).call!

    expect(digest).to be_nil
  end

  it "leaves the other accounts in the digest when a reacting account is blocked" do
    kept = react(actor: create(:actor, uri: "https://kept.example/users/a"))
    blocked = create(:actor, uri: "https://blocked.example/users/b")
    react(actor: blocked)

    Federation::Safety::Blocking.new.block_actor!(actor_uri: blocked.uri)

    expect(digest.payload["count"]).to eq(1)
    expect(digest.actor).to eq(kept.actor)
  end

  it "drops a deleted account from the digest" do
    gone = create(:actor)
    react(actor: gone)
    react

    gone.tombstone!
    Notifications::Withdraw.new(actor: gone).call!

    expect(digest.payload["count"]).to eq(1)
    expect(digest.actor).not_to eq(gone)
  end

  it "goes away with the workout" do
    react

    workout.destroy!

    expect(Notification.where(user: owner, kind: "reaction")).to be_empty
  end

  it "is never created by a refresh" do
    reaction = create(:reaction, workout:)

    Notifications::Withdraw.new(user: owner, kind: "reaction", subject: reaction).call!

    expect(digest).to be_nil
  end
end
