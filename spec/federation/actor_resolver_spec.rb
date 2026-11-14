# frozen_string_literal: true

require "rails_helper"

RSpec.describe Federation::ActorResolver do
  let(:now) { Time.utc(2026, 8, 26, 12) }
  let(:actor_uri) { "https://wanderer.example/users/demo" }
  let(:public_key) { OpenSSL::PKey::RSA.generate(2048) }
  let(:document) do
    {
      "id" => actor_uri,
      "type" => "Person",
      "preferredUsername" => "demo",
      "name" => "Demo Wanderer",
      "summary" => "A remote hiker",
      "inbox" => "https://wanderer.example/users/demo/inbox",
      "endpoints" => { "sharedInbox" => "https://wanderer.example/inbox" },
      "publicKey" => {
        "id" => "#{actor_uri}#main-key",
        "owner" => actor_uri,
        "publicKeyPem" => public_key.public_key.to_pem
      }
    }
  end
  let(:response) do
    Federation::Transport::Client::Response.new(200, { "content-type" => "application/activity+json" }, JSON.generate(document), URI(actor_uri))
  end
  let(:client) { instance_double(Federation::Transport::Client) }
  let(:resolver) { described_class.new(client:, now:) }

  before do
    allow(client).to receive(:validate_url)
    allow(client).to receive(:get).and_return(response)
  end

  it "fetches and caches a validated remote actor" do
    actor = resolver.resolve(actor_uri)

    expect(actor).to be_persisted
    expect(actor).to be_remote
    expect(actor.uri).to eq(actor_uri)
    expect(actor.handle).to eq("demo@wanderer.example")
    expect(actor.public_key_id).to eq("#{actor_uri}#main-key")
    expect(actor.inbox_url).to eq("https://wanderer.example/users/demo/inbox")
    expect(actor.shared_inbox_url).to eq("https://wanderer.example/inbox")

    resolver.resolve(actor_uri)
    expect(client).to have_received(:get).once
  end

  describe "an instance that does not answer" do
    let!(:cached) { resolver.resolve(actor_uri).tap { |actor| actor.update!(last_fetched_at: now - 2.days) } }

    before do
      allow(client).to receive(:get).and_raise(Federation::Transport::Client::NetworkError, "connection refused")
    end

    it "reports it as unavailable" do
      expect { resolver.resolve(actor_uri) }.to raise_error(described_class::Unavailable)
    end

    it "keeps the cached actor when a stale copy is acceptable" do
      expect(resolver.resolve(actor_uri, stale_ok: true)).to eq(cached)
    end

    it "keeps nothing for an actor it never cached" do
      expect { resolver.resolve("https://wanderer.example/users/other", stale_ok: true) }
        .to raise_error(described_class::Unavailable)
    end
  end

  it "tells a gone actor, an overloaded instance and a refusal apart" do
    { 410 => described_class::Gone, 503 => described_class::Unavailable, 429 => described_class::Unavailable }
      .each do |status, error|
        allow(client).to receive(:get).and_return(Federation::Transport::Client::Response.new(status, {}, "", URI(actor_uri)))
        expect { resolver.resolve(actor_uri) }.to raise_error(error)
      end

    allow(client).to receive(:get).and_return(Federation::Transport::Client::Response.new(404, {}, "", URI(actor_uri)))
    expect { resolver.resolve(actor_uri) }.to raise_error(described_class::FetchError) { |error|
      expect(error).not_to be_a(described_class::Unavailable)
    }
  end

  it "stores the resolved WebFinger account instead of reconstructing it" do
    actor = resolver.resolve(actor_uri, acct: "demo@discovery.example:8443")

    expect(actor.acct).to eq("demo@discovery.example:8443")
  end

  it "keeps a non-default port in the derived handle" do
    ported_uri = "https://wanderer.example:8443/users/demo"
    ported = document.merge(
      "id" => ported_uri,
      "publicKey" => document["publicKey"].merge(
        "id" => "#{ported_uri}#main-key", "owner" => ported_uri
      )
    )
    allow(client).to receive(:get).and_return(
      Federation::Transport::Client::Response.new(200, {}, JSON.generate(ported), URI(ported_uri))
    )

    actor = resolver.resolve(ported_uri)

    expect(actor.handle).to eq("demo@wanderer.example:8443")
  end

  it "stores an absolute avatar URL from the actor icon" do
    with_icon = document.merge("icon" => { "type" => "Image", "url" => "https://wanderer.example/avatar.png" })
    allow(client).to receive(:get).and_return(
      Federation::Transport::Client::Response.new(200, {}, JSON.generate(with_icon), URI(actor_uri))
    )

    actor = resolver.resolve(actor_uri)

    expect(actor.avatar_url).to eq("https://wanderer.example/avatar.png")
  end

  it "ignores a malformed avatar URL" do
    with_icon = document.merge("icon" => { "url" => "not-a-url" })
    allow(client).to receive(:get).and_return(
      Federation::Transport::Client::Response.new(200, {}, JSON.generate(with_icon), URI(actor_uri))
    )

    actor = resolver.resolve(actor_uri)

    expect(actor.avatar_url).to be_nil
  end

  it "assigns the locally configured peer capability, never a remote claim" do
    create(:federation_peer_policy, domain: "wanderer.example", capability_profile: "restricted_fetch")
    claimed = document.merge("capability_profile" => "restricted_shared_inbox")
    allow(client).to receive(:get).and_return(
      Federation::Transport::Client::Response.new(200, {}, JSON.generate(claimed), URI(actor_uri))
    )

    actor = resolver.resolve(actor_uri)

    expect(actor.capability_profile).to eq("restricted_fetch")
  end

  it "preserves a stored capability when no policy exists" do
    cached = create(:actor, uri: actor_uri, capability_profile: "restricted_fetch", last_fetched_at: now - 2.hours)

    resolver.resolve(actor_uri)

    expect(cached.reload.capability_profile).to eq("restricted_fetch")
  end

  it "fetches the actor document under the document byte cap" do
    resolver.resolve(actor_uri)

    expect(client).to have_received(:get)
      .with(actor_uri, hash_including(max_bytes: described_class::MAX_DOCUMENT_BYTES))
  end

  it "returns a validated but unsaved actor when asked not to persist" do
    actor = resolver.resolve(actor_uri, persist: false)

    expect(actor).to be_new_record
    expect(actor.public_key_id).to eq("#{actor_uri}#main-key")
    expect(Actor.find_by(uri: actor_uri)).to be_nil

    actor.save!
    expect(Actor.find_by(uri: actor_uri)).to be_present
  end

  it "leaves a stale row untouched when a refresh is not persisted" do
    stale = create(:actor, uri: actor_uri, last_fetched_at: now - 2.hours)

    actor = resolver.resolve(actor_uri, persist: false)

    expect(actor.id).to eq(stale.id)
    expect(actor).to be_changed
    expect(stale.reload.last_fetched_at).to eq(now - 2.hours)
  end

  it "refreshes stale remote actors" do
    create(:actor, uri: actor_uri, last_fetched_at: now - 2.hours)

    resolver.resolve(actor_uri)

    expect(client).to have_received(:get).once
  end

  it "does not cache an actor document with a mismatched id" do
    allow(client).to receive(:get).and_return(
      Federation::Transport::Client::Response.new(200, {}, JSON.generate(document.merge("id" => "https://other.example/users/demo")), URI(actor_uri))
    )

    expect { resolver.resolve(actor_uri) }.to raise_error(described_class::InvalidActor)
    expect(Actor.find_by(uri: actor_uri)).to be_nil
  end

  it "does not replace a local actor" do
    local_actor = create(:actor, :local)

    expect(resolver.resolve(local_actor.uri)).to eq(local_actor)
    expect(client).not_to have_received(:get)
  end

  it "invalidates a remote cache entry" do
    actor = create(:actor, uri: actor_uri, last_fetched_at: now)

    expect(resolver.invalidate!(actor_uri)).to eq(actor)
    expect(actor.reload.last_fetched_at).to be_nil
  end

  it "rejects an unsafe actor endpoint" do
    unsafe = document.merge("inbox" => "http://127.0.0.1:3000/inbox")
    allow(client).to receive(:get).and_return(
      Federation::Transport::Client::Response.new(200, {}, JSON.generate(unsafe), URI(actor_uri))
    )
    allow(client).to receive(:validate_url).with("http://127.0.0.1:3000/inbox").and_raise(Federation::Transport::SsrfGuard::UnsafeUri)

    expect { resolver.resolve(actor_uri) }.to raise_error(described_class::InvalidActor)
    expect(Actor.find_by(uri: actor_uri)).to be_nil
  end

  it "refuses to resolve a blocked actor without fetching it" do
    create(:federation_actor_block, actor_uri:)

    expect { resolver.resolve(actor_uri) }.to raise_error(described_class::InvalidActor, /blocked/)
    expect(client).not_to have_received(:get)
  end

  it "refuses to resolve an actor on a blocked authority" do
    create(:federation_domain_block, domain: "wanderer.example")

    expect { resolver.resolve(actor_uri) }.to raise_error(described_class::InvalidActor, /blocked/)
  end

  it "caps a stored actor summary at 2 000 characters" do
    long = document.merge("summary" => "s" * 3_000)
    allow(client).to receive(:get).and_return(
      Federation::Transport::Client::Response.new(200, {}, JSON.generate(long), URI(actor_uri))
    )

    expect(resolver.resolve(actor_uri).summary.length).to eq(2_000)
  end
end
