# frozen_string_literal: true

require "rails_helper"

RSpec.describe Segments::PublicationPolicy do
  let(:owner) { create(:user) }
  let(:segment) { create(:segment, user: owner, visibility: "public") }
  let(:publication) { create(:segment_publication, :with_gpx, segment:) }

  def allowed?(actor:, resource: :segment, publication: self.publication)
    described_class.new(
      publication:,
      principal: Workouts::PublicationPrincipal.protocol(actor)
    ).allowed?(resource:)
  end

  it "serves a public course to any protocol requester" do
    expect(allowed?(actor: nil)).to be(true)
    expect(allowed?(actor: create(:actor))).to be(true)
  end

  it "refuses an anonymous browser" do
    policy = described_class.new(
      publication:,
      principal: Workouts::PublicationPrincipal.anonymous
    )

    expect(policy.allowed?).to be(false)
  end

  it "refuses an inactive publication" do
    publication.mark_deleted!

    expect(allowed?(actor: nil)).to be(false)
  end

  it "gates media on the verified attachment" do
    expect(allowed?(actor: nil, resource: :gpx)).to be(true)
    expect(allowed?(actor: nil, resource: :track)).to be(true)
    expect(allowed?(actor: nil, resource: :route_image)).to be(false)
    expect(allowed?(actor: nil, resource: :media)).to be(true)
  end

  describe "a followers-only course" do
    let(:owner_actor) { create(:local_actor, user: owner) }
    let(:publication) do
      create(:segment_publication, :with_gpx, segment:, audience: "followers", actor: owner_actor)
    end

    before { allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(true) }

    it "refuses a stranger" do
      expect(allowed?(actor: create(:local_actor))).to be(false)
    end

    it "serves an accepted local follower" do
      follower = create(:local_actor)
      create(:following, :accepted, follower_actor: follower, followed_actor: owner_actor)

      expect(allowed?(actor: follower)).to be(true)
    end

    it "serves an accepted remote follower only with a promoted capability" do
      remote = create(:actor)
      create(:following, :accepted, follower_actor: remote, followed_actor: owner_actor)

      expect(allowed?(actor: remote)).to be(false)

      remote.update_columns(capability_profile: "restricted_fetch")

      expect(allowed?(actor: remote)).to be(true)
    end

    it "serves local followers but no remote one while restricted federation is disabled" do
      allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(false)
      follower = create(:local_actor)
      create(:following, :accepted, follower_actor: follower, followed_actor: owner_actor)
      remote = create(:actor, capability_profile: "restricted_fetch")
      create(:following, :accepted, follower_actor: remote, followed_actor: owner_actor)

      expect(allowed?(actor: follower)).to be(true)
      expect(allowed?(actor: remote)).to be(false)
    end
  end
end
