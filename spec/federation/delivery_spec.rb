# frozen_string_literal: true

require "rails_helper"

RSpec.describe Federation::Outbox::Expander do
  let(:local_actor) { create(:local_actor) }
  let(:remote_one) { create(:actor, uri: "https://remote.example/users/one", inbox_url: "https://remote.example/inbox") }
  let(:remote_two) { create(:actor, uri: "https://remote.example/users/two", inbox_url: "https://remote.example/inbox") }
  let(:event) do
    Federation::Outbox::EventBuilder.new(
      actor: local_actor,
      subject_type: "Actor",
      subject_id: local_actor.id,
      activity_type: "Follow",
      object_uri: local_actor.uri,
      idempotency_key: "fanout:test",
      payload: { "type" => "Follow", "actor" => local_actor.uri, "object" => remote_one.uri },
      audience: { "to" => [ remote_one.uri, remote_two.uri ], "cc" => [] }
    ).call!
  end
  let(:actor_resolver) { instance_double(Federation::ActorResolver) }
  let(:client) { instance_double(Federation::Transport::Client) }

  before do
    allow(actor_resolver).to receive(:resolve).with(remote_one.uri, stale_ok: true).and_return(remote_one)
    allow(actor_resolver).to receive(:resolve).with(remote_two.uri, stale_ok: true).and_return(remote_two)
    allow(client).to receive(:validate_url)
  end

  it "groups actors sharing an inbox into one physical delivery" do
    deliveries = described_class.new(event:, actor_resolver:, client:).call!

    expect(deliveries.size).to eq(1)
    delivery = event.reload.deliveries.first
    expect(delivery.inbox_url).to eq("https://remote.example/inbox")
    expect(delivery.recipients.authorized.pluck(:actor_uri)).to contain_exactly(remote_one.uri, remote_two.uri)
    expect(event.reload).to be_expanded
    expect(Federation::DeliverJob).to have_been_enqueued
  end

  # A follower whose instance restarts during fan-out used to be dropped for
  # good: its stale cache was refetched, the fetch failed, and the event
  # completed without it.
  it "keeps a cached recipient whose instance does not answer during fan-out" do
    remote_one.update!(last_fetched_at: 2.days.ago)
    remote_two.update!(last_fetched_at: 2.days.ago)
    allow(client).to receive(:get).and_raise(Federation::Transport::Client::NetworkError, "connection refused")
    resolver = Federation::ActorResolver.new(client:)

    described_class.new(event:, actor_resolver: resolver, client:).call!

    expect(event.reload.deliveries.sole.recipients.authorized.pluck(:actor_uri))
      .to contain_exactly(remote_one.uri, remote_two.uri)
  end

  it "skips a blocked recipient during fan-out" do
    create(:federation_actor_block, actor_uri: remote_one.uri)

    deliveries = described_class.new(event:, actor_resolver:, client:).call!

    expect(deliveries.size).to eq(1)
    expect(deliveries.first.recipients.authorized.pluck(:actor_uri)).to contain_exactly(remote_two.uri)
  end

  it "fans out accepted followers listed by the local followers collection" do
    remote_one.update!(capability_profile: "restricted_fetch")
    create(:following, :accepted, follower_actor: remote_one, followed_actor: local_actor)
    event = Federation::Outbox::EventBuilder.new(
      actor: local_actor,
      subject_type: "Actor",
      subject_id: local_actor.id,
      activity_type: "Like",
      object_uri: local_actor.uri,
      idempotency_key: "followers:test",
      payload: { "type" => "Like", "actor" => local_actor.uri },
      audience: { "to" => [ "https://www.w3.org/ns/activitystreams#Public" ], "cc" => [ "#{local_actor.uri}/followers" ] }
    ).call!

    described_class.new(event:, actor_resolver:, client:).call!

    expect(event.reload.deliveries.first.recipients.first.actor_uri).to eq(remote_one.uri)
  end

  # M4.5 public-only gate: followers-only Creates fail closed and never expand,
  # even to restricted-capable accepted followers (PLAN_M4_5 §5.2). Restricted
  # followers delivery is M5-only.
  it "fails closed for followers-only Creates even to restricted peers during M4.5" do
    owner = create(:user)
    publication_actor = create(:local_actor, user: owner)
    workout = create(:workout, user: owner)
    profile = create(:publishing_profile, :followers, user: owner)
    publication = create(:workout_publication, workout:, publishing_profile: profile)
    peers = [
      create(:actor, uri: "https://remote.example/users/unknown", inbox_url: "https://remote.example/unknown"),
      create(:actor, uri: "https://remote.example/users/public", inbox_url: "https://remote.example/public"),
      create(:actor, uri: "https://remote.example/users/fetch", inbox_url: "https://remote.example/fetch"),
      create(:actor, uri: "https://remote.example/users/shared", inbox_url: "https://remote.example/shared")
    ]
    peers[1].update!(capability_profile: "public_only")
    peers[2].update!(capability_profile: "restricted_fetch")
    peers[3].update!(capability_profile: "restricted_shared_inbox", shared_inbox_url: "https://remote.example/shared-inbox")
    peers.each { |peer| create(:following, :accepted, follower_actor: peer, followed_actor: publication_actor) }
    event = Federation::Outbox::EventBuilder.new(
      actor: publication_actor,
      subject_type: "WorkoutPublication",
      subject_id: publication.id,
      activity_type: "Create",
      object_uri: publication.object_uri,
      idempotency_key: "publication:#{publication.id}:capabilities",
      payload: { "type" => "Create", "object" => publication.object_uri },
      audience: { "to" => [ "#{publication_actor.uri}/followers" ], "cc" => [] }
    ).call!
    resolver = instance_double(Federation::ActorResolver)
    client = instance_double(Federation::Transport::Client)
    peers.each { |peer| allow(resolver).to receive(:resolve).with(peer.uri, stale_ok: true).and_return(peer) }
    allow(client).to receive(:validate_url)

    described_class.new(event:, actor_resolver: resolver, client:).call!

    recipients = event.reload.deliveries.flat_map { |delivery| delivery.recipients.authorized.pluck(:actor_uri) }
    expect(recipients).to be_empty
  end

  it "delivers a followers-only Create only to promoted accepted peers while restricted federation is on" do
    allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(true)
    owner = create(:user)
    publication_actor = create(:local_actor, user: owner)
    workout = create(:workout, user: owner)
    profile = create(:publishing_profile, :followers, user: owner)
    publication = create(:workout_publication, workout:, publishing_profile: profile)
    peers = [
      create(:actor, uri: "https://remote.example/users/unknown", inbox_url: "https://remote.example/unknown"),
      create(:actor, uri: "https://remote.example/users/public", inbox_url: "https://remote.example/public",
        capability_profile: "public_only"),
      create(:actor, uri: "https://remote.example/users/fetch", inbox_url: "https://remote.example/fetch",
        capability_profile: "restricted_fetch"),
      create(:actor, uri: "https://remote.example/users/shared", inbox_url: "https://remote.example/shared",
        capability_profile: "restricted_shared_inbox", shared_inbox_url: "https://remote.example/shared-inbox")
    ]
    peers.each { |peer| create(:following, :accepted, follower_actor: peer, followed_actor: publication_actor) }
    event = Federation::Outbox::EventBuilder.new(
      actor: publication_actor,
      subject_type: "WorkoutPublication",
      subject_id: publication.id,
      activity_type: "Create",
      object_uri: publication.object_uri,
      idempotency_key: "publication:#{publication.id}:restricted-capabilities",
      payload: { "type" => "Create", "object" => publication.object_uri },
      audience: { "to" => [ "#{publication_actor.uri}/followers" ], "cc" => [] }
    ).call!
    resolver = instance_double(Federation::ActorResolver)
    client = instance_double(Federation::Transport::Client)
    peers.each { |peer| allow(resolver).to receive(:resolve).with(peer.uri, stale_ok: true).and_return(peer) }
    allow(client).to receive(:validate_url)

    described_class.new(event:, actor_resolver: resolver, client:).call!

    recipients = event.reload.deliveries.flat_map { |delivery| delivery.recipients.authorized.pluck(:actor_uri) }
    expect(recipients).to contain_exactly(peers[2].uri, peers[3].uri)
    expect(event.deliveries.exists?(inbox_url: peers[2].inbox_url)).to be(true)
    expect(event.deliveries.exists?(inbox_url: peers[3].shared_inbox_url)).to be(true)
  end
end

RSpec.describe Federation::Delivery::Deliver do
  let(:now) { Time.utc(2026, 8, 26, 12) }
  let(:local_actor) { create(:local_actor) }
  let(:event) do
    create(
      :federation_outbox_event,
      actor: local_actor,
      subject_id: local_actor.id,
      object_uri: local_actor.uri,
      payload: { "type" => "Follow", "actor" => local_actor.uri, "object" => "https://remote.example/users/demo" }
    )
  end
  let(:delivery) { create(:federation_delivery, outbox_event: event, inbox_url: "https://remote.example/inbox") }
  let!(:recipient) { create(:federation_delivery_recipient, delivery:, actor_uri: "https://remote.example/users/demo") }
  let(:client) { instance_double(Federation::Transport::Client) }
  let(:actor_resolver) { instance_double(Federation::ActorResolver) }

  before do
    allow(actor_resolver).to receive(:resolve)
  end

  it "signs and delivers the immutable payload" do
    response = Federation::Transport::Client::Response.new(202, {}, "ignored response", URI(delivery.inbox_url))
    allow(client).to receive(:post).and_return(response)

    described_class.new(delivery:, client:, actor_resolver:, now:).call!

    expect(delivery.reload).to be_delivered
    expect(event.reload).to be_complete
    expect(client).to have_received(:post).with(
      delivery.inbox_url,
      body: kind_of(String),
      headers: include("Signature", "Digest", "Date", "Host", "Content-Type"),
      max_redirects: 0
    )
  end

  # PLAN_M5 §12.6: an event naming its recipients one by one shows each
  # destination only its own actors, never the account's other contacts.
  it "sends each destination only its own actors from an explicit recipient list" do
    listed = %w[https://remote.example/users/demo https://remote.example/users/other https://elsewhere.example/users/eve]
    followers = "#{local_actor.uri}/followers"
    deletion = create(
      :federation_outbox_event, actor: local_actor, subject_id: local_actor.id, object_uri: local_actor.uri,
                                activity_type: "Delete",
                                payload: { "type" => "Delete", "actor" => local_actor.uri, "object" => local_actor.uri,
                                           "recipients" => listed, "to" => [ followers ], "cc" => [] },
                                audience: { "recipients" => listed, "to" => [ followers ], "cc" => [] }
    )
    bodies = %w[https://remote.example/inbox https://remote.example/users/other/inbox].map do |inbox_url|
      destination = create(:federation_delivery, outbox_event: deletion, inbox_url:)
      create(:federation_delivery_recipient, delivery: destination,
                                             actor_uri: inbox_url.include?("other") ? listed[1] : listed[0])
      body = nil
      allow(client).to receive(:post) do |_url, **options|
        body = options.fetch(:body)
        Federation::Transport::Client::Response.new(202, {}, "", URI(inbox_url))
      end
      described_class.new(delivery: destination, client:, actor_resolver:, now:).call!
      JSON.parse(body)
    end

    expect(bodies.first["recipients"]).to eq(listed.first(2))
    expect(bodies.first["to"]).to eq([ followers ])
    expect(bodies.first.to_json).not_to include("elsewhere.example")
    expect(bodies.last).to eq(bodies.first)
    expect(deletion.reload.payload["recipients"]).to eq(listed)
  end

  it "fails an inbox that redirects instead of following it" do
    allow(client).to receive(:post).and_raise(Federation::Transport::Client::TooManyRedirects)

    described_class.new(delivery:, client:, actor_resolver:, now:).call!

    expect(delivery.reload).to be_failed
    expect(delivery.last_error).to include("redirected")
  end

  it "retries temporary responses without storing the response body" do
    allow(client).to receive(:post).and_return(
      Federation::Transport::Client::Response.new(503, {}, "secret response body", URI(delivery.inbox_url))
    )
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    described_class.new(delivery:, client:, actor_resolver:, now:).call!

    expect(delivery.reload).to be_retrying
    expect(delivery.last_error).to include("503")
    expect(delivery.last_error).not_to include("secret")
    expect(Federation::DeliverJob).to have_been_enqueued
  end

  # A receiver usually answers 401 because it could not fetch our key at that
  # moment; giving up on the first one lost the activity for good.
  it "retries an unauthorized response" do
    allow(client).to receive(:post).and_return(
      Federation::Transport::Client::Response.new(401, {}, "", URI(delivery.inbox_url))
    )

    described_class.new(delivery:, client:, actor_resolver:, now:).call!

    expect(delivery.reload).to be_retrying
    expect(delivery.last_response_status).to eq(401)
  end

  it "re-resolves one Gone delivery and retries on a new inbox" do
    # Not persisted: pre-POST reauthorization finds no Actor row and keeps the
    # stale inbox, so the 410 path is exercised and recovery moves to the
    # refreshed inbox (PLAN_M4_5 Slice 5).
    replacement = build(:actor, uri: recipient.actor_uri, inbox_url: "https://remote.example/new-inbox")
    allow(actor_resolver).to receive(:resolve).with(recipient.actor_uri, refresh: true).and_return(replacement)
    allow(client).to receive(:validate_url)
    allow(client).to receive(:post).and_return(
      Federation::Transport::Client::Response.new(410, {}, "", URI(delivery.inbox_url))
    )
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    described_class.new(delivery:, client:, actor_resolver:, now:).call!

    expect(delivery.reload).to be_retrying
    expect(delivery.inbox_url).to eq(replacement.inbox_url)
    expect(delivery.gone_recovery_used).to be(true)
    expect(actor_resolver).to have_received(:resolve).with(recipient.actor_uri, refresh: true)
  end

  it "terminates after a second Gone response" do
    delivery.update!(gone_recovery_used: true)
    allow(client).to receive(:post).and_return(
      Federation::Transport::Client::Response.new(410, {}, "", URI(delivery.inbox_url))
    )

    described_class.new(delivery:, client:, actor_resolver:, now:).call!

    expect(delivery.reload).to be_failed
    expect(actor_resolver).not_to have_received(:resolve)
  end
end
