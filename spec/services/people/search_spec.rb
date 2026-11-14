# frozen_string_literal: true

require "rails_helper"

RSpec.describe People::Search do
  let(:viewer) { create(:user, username: "viewer") }

  def search(query, federation_enabled: true)
    described_class.new(viewer:, query:, federation_enabled:).call
  end

  def provision(user) = Federation::ActorProvisioner.new(user:).call!

  it "finds a discoverable account by username prefix" do
    marie = create(:user, username: "marie", display_name: "Marie Dufour", discoverable: "members")

    results = search("mar")

    expect(results.map(&:user)).to eq([ marie ])
    expect(results.first).to be_local
    expect(results.first.handle).to eq("@marie")
  end

  it "finds a discoverable account by display-name prefix, ignoring accents and case" do
    create(:user, username: "paul", display_name: "Élodie Martin", discoverable: "members")

    expect(search("elo").map(&:name)).to eq([ "Élodie Martin" ])
    expect(search("ÉLO").map(&:name)).to eq([ "Élodie Martin" ])
  end

  it "never returns an account that is not discoverable" do
    create(:user, username: "hidden", display_name: "Hidden Person")

    expect(search("hid")).to be_empty
  end

  it "never returns a suspended or deletion-scheduled account" do
    create(:user, username: "suspended", discoverable: "members", suspended_at: Time.current)
    create(:user, username: "leaving", discoverable: "members", deletion_requested_at: Time.current,
                  deletion_scheduled_at: 3.days.from_now, deletion_requested_by: "self")

    expect(search("sus")).to be_empty
    expect(search("lea")).to be_empty
  end

  it "never returns the viewer" do
    viewer.update!(discoverable: "members")

    expect(search("vie")).to be_empty
  end

  it "requires at least three characters" do
    create(:user, username: "marie", discoverable: "members")

    expect(search("ma")).to be_empty
    expect(search("mar").map(&:user)).to eq(User.where(username: "marie").to_a)
  end

  it "caps the result list" do
    10.times { |index| create(:user, username: "runner#{index}", discoverable: "members") }

    expect(search("run").size).to eq(described_class::LIMIT)
  end

  it "reports the viewer's relationship with a result" do
    followed = create(:user, username: "followed", discoverable: "members")
    follower = create(:user, username: "follower", discoverable: "members")
    followed_actor = provision(followed)
    follower_actor = provision(follower)
    local_actor = provision(viewer)
    create(:following, :accepted, follower_actor: local_actor, followed_actor: followed_actor,
                                 uri: "https://remote.example/activities/follow-out")
    create(:following, :accepted, follower_actor: follower_actor, followed_actor: local_actor,
                                 uri: "https://remote.example/activities/follow-in")

    results = search("follow")

    expect(results.find { |result| result.user == followed }).to be_following
    expect(results.find { |result| result.user == follower }).to be_follower
  end

  context "with remote accounts" do
    let(:local_actor) { provision(viewer) }
    let(:remote) { create(:actor, uri: "https://remote.example/users/demo", acct: "demo@remote.example") }

    before do
      create(:following, :accepted, follower_actor: local_actor, followed_actor: remote,
                                   uri: "https://remote.example/activities/follow-remote")
    end

    it "finds a remote account the viewer already follows" do
      expect(search("dem").map(&:actor)).to eq([ remote ])
    end

    it "does not search the whole remote cache" do
      create(:actor, uri: "https://remote.example/users/stranger", acct: "stranger@remote.example")

      expect(search("str")).to be_empty
    end

    it "hides a blocked remote account" do
      FederationActorBlock.create!(actor_uri: remote.uri)

      expect(search("dem")).to be_empty
    end

    it "hides a tombstoned remote account" do
      remote.update!(tombstoned_at: Time.current)

      expect(search("dem")).to be_empty
    end

    it "returns nothing remote while federation is off" do
      expect(search("dem", federation_enabled: false)).to be_empty
    end
  end
end
