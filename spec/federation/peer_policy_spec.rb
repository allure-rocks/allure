# frozen_string_literal: true

require "rails_helper"

RSpec.describe FederationPeerPolicy do
  it "reads the locally assigned capability for a domain or actor URI" do
    create(:federation_peer_policy, domain: "wanderer.example", capability_profile: "restricted_fetch")

    expect(Federation::PeerPolicy.capability_for("wanderer.example")).to eq("restricted_fetch")
    expect(Federation::PeerPolicy.capability_for("https://wanderer.example/users/demo")).to eq("restricted_fetch")
    expect(Federation::PeerPolicy.capability_for("https://other.example/users/demo")).to be_nil
  end

  it "assigns the capability to existing remote actors of the domain" do
    peer = create(:actor, uri: "https://wanderer.example/users/demo")
    other = create(:actor, uri: "https://other.example/users/demo")

    create(:federation_peer_policy, domain: "wanderer.example", capability_profile: "restricted_fetch")

    expect(peer.reload.capability_profile).to eq("restricted_fetch")
    expect(other.reload.capability_profile).to eq("unknown")
  end

  it "demotes actors back to unknown when the policy is destroyed" do
    peer = create(:actor, uri: "https://wanderer.example/users/demo")
    policy = create(:federation_peer_policy, domain: "wanderer.example", capability_profile: "restricted_fetch")

    policy.destroy!

    expect(peer.reload.capability_profile).to eq("unknown")
  end

  it "normalizes and validates the domain" do
    policy = described_class.new(domain: "  Wanderer.Example ", capability_profile: "public_only")
    expect(policy).to be_valid
    expect(policy.domain).to eq("wanderer.example")

    expect(described_class.new(domain: "https://wanderer.example", capability_profile: "public_only")).not_to be_valid
    expect(described_class.new(domain: "wanderer.example", capability_profile: "made_up")).not_to be_valid
  end
end
