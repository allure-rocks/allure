# frozen_string_literal: true

require "rails_helper"

RSpec.describe Federation::TargetResolver do
  let(:config) { Allure::Federation.config }
  let(:actor_resolver) { instance_double(Federation::ActorResolver) }
  let(:webfinger_resolver) { instance_double(Federation::WebFingerResolver) }
  let(:remote) do
    build(:actor, uri: "https://remote.example/users/demo", handle: "demo@remote.example", acct: "demo@remote.example")
  end

  subject(:resolver) { described_class.new(actor_resolver:, webfinger_resolver:, config:) }

  before do
    allow(actor_resolver).to receive(:resolve)
    allow(webfinger_resolver).to receive(:resolve)
  end

  it "routes a bare name@domain through WebFinger" do
    expect(webfinger_resolver).to receive(:resolve).with("demo@remote.example").and_return(remote)
    expect(actor_resolver).not_to receive(:resolve)

    expect(resolver.call!("demo@remote.example")).to eq(remote)
  end

  it "routes a handle with a non-default port through WebFinger" do
    expect(webfinger_resolver).to receive(:resolve).with("demo@remote.example:8443").and_return(remote)

    expect(resolver.call!("demo@remote.example:8443")).to eq(remote)
  end

  it "routes @handles and acct values through WebFinger" do
    expect(webfinger_resolver).to receive(:resolve).with("@demo@remote.example").and_return(remote)
    expect(webfinger_resolver).to receive(:resolve).with("acct:demo@remote.example").and_return(remote)

    expect(resolver.call!("@demo@remote.example")).to eq(remote)
    expect(resolver.call!("acct:demo@remote.example")).to eq(remote)
  end

  it "treats an absolute URI as an actor URI, never a handle" do
    uri = "https://remote.example/@demo"
    expect(actor_resolver).to receive(:resolve).with(uri).and_return(remote)
    expect(webfinger_resolver).not_to receive(:resolve)

    expect(resolver.call!(uri)).to eq(remote)
  end

  it "treats a value with a scheme as an actor URI" do
    value = "mailto:demo@remote.example"
    expect(actor_resolver).to receive(:resolve).with(value).and_return(remote)
    expect(webfinger_resolver).not_to receive(:resolve)

    expect(resolver.call!(value)).to eq(remote)
  end

  it "resolves a bare local username or local handle locally" do
    create(:user, username: "marie")

    expect(resolver.call!("marie").user.username).to eq("marie")
    expect(resolver.call!(config.handle("marie")).user.username).to eq("marie")
    expect(actor_resolver).not_to have_received(:resolve)
    expect(webfinger_resolver).not_to have_received(:resolve)
  end

  it "rejects a blank target" do
    expect { resolver.call!(" ") }.to raise_error(described_class::InvalidTarget)
  end
end
