# frozen_string_literal: true

require "rails_helper"

RSpec.describe Profiles::SharingPolicy do
  let(:user) { create(:user) }
  let(:viewer) { create(:user) }
  subject(:policy) { described_class.new(user:, viewer:) }

  def follow(status: "accepted", reverse: false)
    owner_actor = Federation::ActorProvisioner.new(user:).call!
    viewer_actor = Federation::ActorProvisioner.new(user: viewer).call!
    create(:following, follower_actor: reverse ? owner_actor : viewer_actor,
                       followed_actor: reverse ? viewer_actor : owner_actor,
                       status:, accepted_at: (Time.current if status == "accepted"),
                       undone_at: (Time.current if status == "undone"))
  end

  it "shares nothing for none, even with the owner" do
    expect(policy.allowed?(audience: "none")).to be(false)
    expect(described_class.new(user:, viewer: user).allowed?(audience: "none")).to be(false)
  end

  it "serves the members audience without requiring a follow or actors" do
    expect(user).not_to receive(:actor)
    expect(viewer).not_to receive(:actor)

    expect(policy.allowed?(audience: "members")).to be(true)
  end

  it "serves the owner of a followers-only section without requiring an actor" do
    expect(user).not_to receive(:actor)

    expect(described_class.new(user:, viewer: user).allowed?(audience: "followers")).to be(true)
  end

  it "serves an accepted local follower without depending on restricted federation" do
    follow
    expect(Allure::Federation::Config).not_to receive(:restricted_enabled?)

    expect(policy.allowed?(audience: "followers")).to be(true)
  end

  %w[pending rejected undone].each do |status|
    it "refuses a #{status} follower" do
      follow(status:)

      expect(policy.allowed?(audience: "followers")).to be(false)
    end
  end

  it "refuses a reverse-direction follow" do
    follow(reverse: true)

    expect(policy.allowed?(audience: "followers")).to be(false)
  end

  it "refuses an unrelated account or a missing local actor" do
    expect(policy.allowed?(audience: "followers")).to be(false)
  end

  it "does not serve a tombstoned follower" do
    follow.follower_actor.tombstone!
    viewer.reload

    expect(policy.allowed?(audience: "followers")).to be(false)
  end

  it "does not serve anonymous, unregistered or remote actor principals" do
    [ nil, build(:user), create(:actor) ].each do |principal|
      %w[members followers].each do |audience|
        expect(described_class.new(user:, viewer: principal).allowed?(audience:)).to be(false)
      end
    end
  end

  it "does not serve a deactivated owner or viewer" do
    viewer.suspended_at = Time.current
    expect(policy.allowed?(audience: "members")).to be(false)
    viewer.suspended_at = nil
    user.deletion_scheduled_at = 7.days.from_now

    expect(policy.allowed?(audience: "members")).to be(false)
    expect(described_class.new(user:, viewer: user).allowed?(audience: "followers")).to be(false)
  end

  it "refuses every unknown audience" do
    [ nil, "", "public", "private", "true" ].each do |audience|
      expect(policy.allowed?(audience:)).to be(false)
    end
  end
end
