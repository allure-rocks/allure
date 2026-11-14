# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Slice 5 delivery hardening" do
  let(:owner) { create(:user) }
  let(:owner_actor) { create(:local_actor, user: owner) }
  let(:workout) { create(:workout, user: owner) }
  let!(:track_segment) { create(:track_segment, workout:) }
  let(:profile) { create(:publishing_profile, :without_endpoint_masks, user: owner) }
  let(:publication) { publish_workout!(user: owner, workout:, profile:) }
  let(:create_event) do
    FederationOutboxEvent.find_by!(activity_type: "Create", object_uri: publication.object_uri)
  end
  let(:remote) do
    create(
      :actor,
      inbox_url: "https://remote.example/inbox",
      capability_profile: "public_only"
    )
  end
  let(:client) { instance_double(Federation::Transport::Client) }

  before do
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    create(:following, :accepted, follower_actor: remote, followed_actor: owner_actor)
    allow(client).to receive(:validate_url)
    # Publications defer their route image to the route_images worker; the
    # Create intent is `preparing` until that job finalizes it.
    allow_any_instance_of(Workouts::MaplibreRouteImageRenderer).to receive(:call)
      .and_raise(Workouts::MaplibreRouteImageRenderer::RenderingError, "no browser")
    Workouts::RenderPublicationRouteImageJob.perform_now(publication)
  end

  after { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }

  def expand!
    resolver = instance_double(Federation::ActorResolver)
    allow(resolver).to receive(:resolve).with(remote.uri, stale_ok: true).and_return(remote)
    Federation::Outbox::Expander.new(event: create_event, actor_resolver: resolver, client:).call!
  end

  it "recalculates authorization before POST after unfollow" do
    expand!
    delivery = create_event.deliveries.first
    Following.find_by!(follower_actor: remote, followed_actor: owner_actor).undo!
    allow(client).to receive(:post)

    Federation::Delivery::Deliver.new(delivery:, client:, now: Time.current).call!

    expect(delivery.reload).to be_cancelled
    expect(client).not_to have_received(:post)
  end

  it "recalculates authorization before POST after tombstone" do
    expand!
    delivery = create_event.deliveries.first
    remote.tombstone!
    allow(client).to receive(:post)

    Federation::Delivery::Deliver.new(delivery:, client:, now: Time.current).call!

    expect(delivery.reload).to be_cancelled
    expect(client).not_to have_received(:post)
  end

  it "orders Delete after the logical Create attempt, not the old inbox URL" do
    expand!
    create_delivery = create_event.deliveries.first
    create_delivery.update!(status: "delivering", lease_until: 5.minutes.from_now)
    withdrawal = Workouts::PublicationWithdrawal.new(user: owner, workout:).call!
    delete_event = withdrawal.delete_event
    delete_resolver = instance_double(Federation::ActorResolver)
    allow(delete_resolver).to receive(:resolve).with(remote.uri, stale_ok: true).and_return(remote)
    Federation::Outbox::Expander.new(event: delete_event, actor_resolver: delete_resolver, client:).call!
    delete_delivery = delete_event.deliveries.first
    delete_delivery.update!(inbox_url: "https://remote.example/new-inbox")
    allow(client).to receive(:post).and_return(
      Federation::Transport::Client::Response.new(202, {}, "", URI("https://remote.example/new-inbox"))
    )

    Federation::Delivery::Deliver.new(delivery: delete_delivery, client:, now: Time.current).call!

    expect(delete_delivery.reload).to be_retrying
    expect(client).not_to have_received(:post)
  end

  it "posts to the recalculated inbox when the actor inbox changes before POST" do
    expand!
    delivery = create_event.deliveries.first
    remote.update!(inbox_url: "https://remote.example/rotated-inbox")
    posted_urls = []
    allow(client).to receive(:post) do |url, **|
      posted_urls << url
      Federation::Transport::Client::Response.new(202, {}, "", URI(url))
    end

    Federation::Delivery::Deliver.new(delivery:, client:, now: Time.current).call!

    expect(posted_urls).to eq([ "https://remote.example/rotated-inbox" ])
    expect(delivery.reload.inbox_url).to eq("https://remote.example/rotated-inbox")
    expect(delivery).to be_delivered
  end

  it "preserves locally assigned capability across actor refresh" do
    remote.update!(capability_profile: "restricted_fetch")
    document = {
      "id" => remote.uri,
      "type" => "Person",
      "preferredUsername" => "remote",
      "publicKey" => {
        "id" => "#{remote.uri}#main-key",
        "owner" => remote.uri,
        "publicKeyPem" => OpenSSL::PKey::RSA.generate(2048).public_key.to_pem
      },
      "inbox" => "https://remote.example/new-personal-inbox",
      "endpoints" => {}
    }
    response = Federation::Transport::Client::Response.new(
      200, {}, JSON.generate(document), URI(remote.uri)
    )
    fetch_client = instance_double(Federation::Transport::Client)
    allow(fetch_client).to receive(:validate_url)
    allow(fetch_client).to receive(:get).and_return(response)

    refreshed = Federation::ActorResolver.new(client: fetch_client).resolve(remote.uri, refresh: true)

    expect(refreshed.capability_profile).to eq("restricted_fetch")
    expect(refreshed.inbox_url).to eq("https://remote.example/new-personal-inbox")
  end
end
