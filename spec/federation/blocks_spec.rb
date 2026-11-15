# frozen_string_literal: true

require "rails_helper"

RSpec.describe Federation::Safety::Blocks do
  it "detects a blocked actor" do
    create(:federation_actor_block, actor_uri: "https://blocked.example/users/demo")

    expect(described_class.blocked?("https://blocked.example/users/demo")).to be(true)
    expect(described_class.blocked_actor?("https://blocked.example/users/demo")).to be(true)
    expect(described_class.blocked?("https://blocked.example/users/other")).to be(false)
  end

  it "detects a blocked domain including a non-default port" do
    create(:federation_domain_block, domain: "blocked.example:8443")

    expect(described_class.blocked_domain?("blocked.example:8443")).to be(true)
    expect(described_class.blocked?("https://blocked.example:8443/users/demo")).to be(true)
    expect(described_class.blocked?("https://blocked.example/users/demo")).to be(false)
  end

  # docs/dev/FEDERATION.md: a blocked operator must not come back on a subdomain or
  # another port of the same domain.
  it "covers every subdomain and port of a domain blocked without a port" do
    create(:federation_domain_block, domain: "evil.example")

    %w[
      https://evil.example/users/a https://x.evil.example/users/a https://a.b.EVIL.example/users/a
      https://evil.example:8443/users/a https://x.evil.example:8443/users/a
    ].each { |uri| expect(described_class.blocked?(uri)).to be(true), uri }
    %w[https://notevil.example/users/a https://evil.example.org/users/a https://example/users/a]
      .each { |uri| expect(described_class.blocked?(uri)).to be(false), uri }
    expect(described_class.blocked_domain?("x.evil.example:8443")).to be(true)
  end

  it "covers only that authority for a domain blocked with a port" do
    create(:federation_domain_block, domain: "evil.example:8443")

    expect(described_class.blocked?("https://evil.example:8443/users/a")).to be(true)
    expect(described_class.blocked?("https://evil.example/users/a")).to be(false)
    expect(described_class.blocked?("https://x.evil.example:8443/users/a")).to be(false)
  end

  it "never treats the parent labels of an IP address as a domain" do
    create(:federation_domain_block, domain: "3.4")

    expect(described_class.blocked?("https://1.2.3.4/users/a")).to be(false)
  end

  it "applies the same coverage to a batch of URIs" do
    create(:federation_domain_block, domain: "evil.example")

    blocked = described_class.blocked_uris(%w[https://x.evil.example:8443/users/a https://fine.example/users/b])

    expect(blocked).to contain_exactly("https://x.evil.example:8443/users/a")
  end

  it "resolves a batch of URIs against actor and domain blocks" do
    create(:federation_actor_block, actor_uri: "https://blocked.example/users/demo")
    create(:federation_domain_block, domain: "banned.example")

    blocked = described_class.blocked_uris(
      [ "https://blocked.example/users/demo", "https://banned.example/users/other", "https://fine.example/users/ok" ]
    )

    expect(blocked).to contain_exactly("https://blocked.example/users/demo", "https://banned.example/users/other")
  end

  it "matches an actor block regardless of host case" do
    create(:federation_actor_block, actor_uri: "https://blocked.example/users/demo")

    expect(described_class.blocked_actor?("https://BLOCKED.example/users/demo")).to be(true)
    expect(described_class.blocked?("https://Blocked.Example/users/demo")).to be(true)
    expect(described_class.blocked_actor?("https://blocked.example/users/other")).to be(false)
  end

  it "stores an actor block with a folded host" do
    block = FederationActorBlock.create!(actor_uri: "https://BLOCKED.example/Users/Demo")

    expect(block.actor_uri).to eq("https://blocked.example/Users/Demo")
  end

  it "normalizes and validates domain blocks" do
    block = FederationDomainBlock.new(domain: " Blocked.Example ")
    expect(block).to be_valid
    expect(block.domain).to eq("blocked.example")

    expect(FederationDomainBlock.new(domain: "https://blocked.example")).not_to be_valid
  end

  it "validates actor block URIs" do
    expect(FederationActorBlock.new(actor_uri: "not a uri")).not_to be_valid
    expect(FederationActorBlock.new(actor_uri: "https://blocked.example/users/demo")).to be_valid
  end
end
