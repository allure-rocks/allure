# frozen_string_literal: true

require "rails_helper"

RSpec.describe Federation::WebFingerResolver do
  let(:actor) { create(:actor, uri: "https://wanderer.example/users/demo") }
  let(:client) { instance_double(Federation::Transport::Client) }
  let(:actor_resolver) { instance_double(Federation::ActorResolver) }
  let(:response) do
    Federation::Transport::Client::Response.new(
      200,
      { "content-type" => Allure::Federation::MediaTypes::WEBFINGER },
      JSON.generate(
        "subject" => "acct:demo@wanderer.example",
        "links" => [
          { "rel" => "self", "type" => Allure::Federation::MediaTypes::ACTIVITY_PUB, "href" => actor.uri }
        ]
      ),
      URI("https://wanderer.example/.well-known/webfinger")
    )
  end
  let(:secure_config) do
    Allure::Federation::Config.new(base_url: "https://allure.example", protocol: "https")
  end
  let(:resolver) { described_class.new(client:, actor_resolver:, config: secure_config) }

  before do
    allow(client).to receive(:get).and_return(response)
    allow(actor_resolver).to receive(:resolve).and_return(actor)
  end

  it "resolves a remote handle through the WebFinger self link" do
    expect(resolver.resolve("@demo@wanderer.example")).to eq(actor)
    expect(client).to have_received(:get).with(
      "https://wanderer.example/.well-known/webfinger?resource=acct%3Ademo%40wanderer.example",
      headers: { "Accept" => Allure::Federation::MediaTypes::WEBFINGER }
    )
    expect(actor_resolver).to have_received(:resolve)
      .with(actor.uri, acct: "demo@wanderer.example")
  end

  # A handle carries no scheme. On the Tier-2 ring both nodes speak plain HTTP,
  # so hardcoding HTTPS here would make follow-by-handle impossible locally
  # while FEDERATION_PROTOCOL claims to control exactly this.
  it "discovers over the configured protocol and keeps a non-default port" do
    ring_config = Allure::Federation::Config.new(
      base_url: "http://allure-a.test:3001", protocol: "http", allow_private_ips: true
    )
    allow(client).to receive(:get).and_return(
      Federation::Transport::Client::Response.new(
        200,
        { "content-type" => Allure::Federation::MediaTypes::WEBFINGER },
        JSON.generate(
          "subject" => "acct:marie@allure-b.test:3002",
          "links" => [
            { "rel" => "self", "type" => Allure::Federation::MediaTypes::ACTIVITY_PUB, "href" => "http://allure-b.test:3002/users/marie" }
          ]
        ),
        URI("http://allure-b.test:3002/.well-known/webfinger")
      )
    )

    described_class.new(client:, actor_resolver:, config: ring_config).resolve("@marie@allure-b.test:3002")

    expect(client).to have_received(:get).with(
      "http://allure-b.test:3002/.well-known/webfinger?resource=acct%3Amarie%40allure-b.test%3A3002",
      headers: { "Accept" => Allure::Federation::MediaTypes::WEBFINGER }
    )
    expect(actor_resolver).to have_received(:resolve)
      .with("http://allure-b.test:3002/users/marie", acct: "marie@allure-b.test:3002")
  end

  # A domain may only vouch for actors on its own authority. Without the
  # binding, a WebFinger server could alias another instance's actor under its
  # own handle and have it cached with a foreign acct.
  it "rejects a self link that points at another authority" do
    allow(client).to receive(:get).and_return(
      Federation::Transport::Client::Response.new(
        200,
        { "content-type" => Allure::Federation::MediaTypes::WEBFINGER },
        JSON.generate(
          "subject" => "acct:demo@wanderer.example",
          "links" => [
            { "rel" => "self", "type" => Allure::Federation::MediaTypes::ACTIVITY_PUB, "href" => "https://victim.example/users/demo" }
          ]
        ),
        URI("https://wanderer.example/.well-known/webfinger")
      )
    )

    expect { resolver.resolve("@demo@wanderer.example") }
      .to raise_error(described_class::InvalidHandle, /does not belong/)
    expect(actor_resolver).not_to have_received(:resolve)
  end

  it "rejects a self link on a different port of the queried host" do
    allow(client).to receive(:get).and_return(
      Federation::Transport::Client::Response.new(
        200,
        { "content-type" => Allure::Federation::MediaTypes::WEBFINGER },
        JSON.generate(
          "subject" => "acct:demo@wanderer.example:8443",
          "links" => [
            { "rel" => "self", "type" => Allure::Federation::MediaTypes::ACTIVITY_PUB, "href" => "https://wanderer.example/users/demo" }
          ]
        ),
        URI("https://wanderer.example:8443/.well-known/webfinger")
      )
    )

    expect { resolver.resolve("@demo@wanderer.example:8443") }
      .to raise_error(described_class::InvalidHandle, /does not belong/)
  end

  it "rejects a local handle without making a network request" do
    local = described_class.new(client:, actor_resolver:)

    expect { local.resolve("@marie@#{Allure::Federation.config.domain}") }
      .to raise_error(described_class::InvalidHandle)
    expect(client).not_to have_received(:get)
  end

  it "reports an unreachable instance as a fetch error" do
    allow(client).to receive(:get).and_raise(Federation::Transport::Client::NetworkError, "wrong version number")

    expect { resolver.resolve("@demo@wanderer.example") }.to raise_error(described_class::FetchError)
  end

  it "rejects a WebFinger response without a matching self link" do
    allow(client).to receive(:get).and_return(
      Federation::Transport::Client::Response.new(200, {}, JSON.generate("links" => []), URI("https://wanderer.example/.well-known/webfinger"))
    )

    expect { resolver.resolve("@demo@wanderer.example") }.to raise_error(described_class::InvalidHandle)
  end
end
