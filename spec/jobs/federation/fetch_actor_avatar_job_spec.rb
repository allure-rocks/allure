# frozen_string_literal: true

require "rails_helper"

RSpec.describe Federation::FetchActorAvatarJob do
  let(:actor) do
    create(
      :actor,
      uri: "https://remote.example/users/demo",
      avatar_url: "https://remote.example/avatar.png"
    )
  end
  let(:client) { instance_double(Federation::Transport::Client) }
  let(:png) do
    Vips::Image.black(64, 64).write_to_buffer(".png")
  end

  before do
    allow(Federation::Transport::Client).to receive(:new).and_return(client)
    allow(client).to receive(:get).and_return(
      Federation::Transport::Client::Response.new(200, {}, png, URI(actor.avatar_url))
    )
  end

  it "caches a verified image and records the fetch" do
    described_class.perform_now(actor.id)

    expect(actor.reload).to be_avatar_cached
    expect(actor.avatar_cache.content_type).to eq("image/png")
    expect(actor.avatar_cached_at).to be_present
  end

  it "ignores non-image bytes" do
    allow(client).to receive(:get).and_return(
      Federation::Transport::Client::Response.new(200, {}, "not an image", URI(actor.avatar_url))
    )

    described_class.perform_now(actor.id)

    expect(actor.reload).not_to be_avatar_cached
  end

  it "ignores an oversized image" do
    allow(client).to receive(:get).and_return(
      Federation::Transport::Client::Response.new(200, {}, Vips::Image.black(4096, 4096).write_to_buffer(".png"), URI(actor.avatar_url))
    )

    described_class.perform_now(actor.id)

    expect(actor.reload).not_to be_avatar_cached
  end

  it "stays silent when the fetch fails" do
    allow(client).to receive(:get).and_raise(Federation::Transport::Client::NetworkError, "unreachable")

    expect { described_class.perform_now(actor.id) }.not_to raise_error
    expect(actor.reload).not_to be_avatar_cached
  end

  it "ignores a tombstoned actor" do
    actor.tombstone!

    described_class.perform_now(actor.id)

    expect(actor.reload).not_to be_avatar_cached
  end

  it "ignores a blocked actor" do
    create(:federation_actor_block, actor_uri: actor.uri)

    described_class.perform_now(actor.id)

    expect(actor.reload).not_to be_avatar_cached
    expect(client).not_to have_received(:get)
  end

  it "ignores an actor on a blocked authority" do
    create(:federation_domain_block, domain: "remote.example")

    described_class.perform_now(actor.id)

    expect(actor.reload).not_to be_avatar_cached
  end
end
