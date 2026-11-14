# frozen_string_literal: true

require "rails_helper"

RSpec.describe Federation::RelationshipRepair do
  let(:local) { create(:local_actor) }
  let(:deleted) { create(:actor, uri: "https://gone.example/users/old") }
  let(:blocked) { create(:actor, uri: "https://blocked.example/users/demo") }
  let(:healthy) { create(:actor, uri: "https://fine.example/users/demo") }
  let!(:to_deleted) { create(:following, :accepted, follower_actor: local, followed_actor: deleted) }
  let!(:from_blocked) do
    create(:following, :accepted, follower_actor: blocked, followed_actor: local,
                                  uri: "https://blocked.example/activities/follow-1")
  end
  let!(:to_healthy) { create(:following, :accepted, follower_actor: local, followed_actor: healthy) }

  before do
    deleted.tombstone!
    create(:federation_domain_block, domain: "blocked.example")
  end

  it "reports the relationships left with deleted or blocked accounts without changing them" do
    findings = described_class.new.call

    expect(findings.map { [ it.following, it.reason ] })
      .to contain_exactly([ to_deleted, "deleted" ], [ from_blocked, "blocked" ])
    expect(Following.active.count).to eq(3)
  end

  it "ends them when applied, and finds nothing the second time" do
    described_class.new.call(apply: true)

    expect([ to_deleted.reload, from_blocked.reload ]).to all(be_undone)
    expect(to_healthy.reload).to be_accepted
    expect(described_class.new.call).to be_empty
  end
end
