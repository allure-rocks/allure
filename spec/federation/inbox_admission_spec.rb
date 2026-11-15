# frozen_string_literal: true

require "rails_helper"

RSpec.describe Federation::Inbox::Admission do
  let(:now) { Time.utc(2026, 8, 26, 12) }
  let(:recipient) { create(:local_actor) }
  let(:remote_key) { OpenSSL::PKey::RSA.generate(2048) }
  let(:actor_uri) { "https://remote.example/users/demo" }
  let(:remote_actor) do
    create(
      :actor,
      uri: actor_uri,
      public_key_id: "#{actor_uri}#main-key",
      public_key_pem: remote_key.public_key.to_pem,
      inbox_url: "https://remote.example/users/demo/inbox"
    )
  end
  let(:activity) do
    {
      "id" => "https://remote.example/activities/follow-1",
      "type" => "Follow",
      "actor" => actor_uri,
      "object" => recipient.uri
    }
  end
  let(:body) { JSON.generate(activity) }
  let(:path) { "/users/#{recipient.user.username}/inbox" }
  let(:headers) { signed_headers_for(activity) }

  def signed_headers_for(document, key_id: remote_actor.public_key_id, key: remote_key)
    request_body = JSON.generate(document)
    digest = "SHA-256=#{Base64.strict_encode64(Digest::SHA256.digest(request_body.b))}"
    values = {
      "host" => "allure.test:3000",
      "date" => now.httpdate,
      "digest" => digest,
      "content-type" => Allure::Federation::MediaTypes::ACTIVITY_PUB
    }
    signed_headers = %w[(request-target) host date digest content-type]
    canonical = Allure::Federation::Signature::CanonicalRequest.new(
      method: "POST", path:, headers: values, signed_headers:
    ).call
    signature = key.sign(OpenSSL::Digest::SHA256.new, canonical)
    values.merge(
      "Signature" => %(keyId="#{key_id}",algorithm="rsa-sha256",headers="#{signed_headers.join(" ")}",signature="#{Base64.strict_encode64(signature)}")
    )
  end
  let(:actor_resolver) { instance_double(Federation::ActorResolver) }
  let(:verifier) { Federation::Signature::Verifier.new(now:) }
  let(:admission) do
    described_class.new(
      method: "POST",
      path:,
      content_type: Allure::Federation::MediaTypes::ACTIVITY_PUB,
      headers:,
      body:,
      recipient_actor: recipient,
      actor_resolver:,
      verifier:
    )
  end

  before do
    allow(actor_resolver).to receive(:resolve).with(actor_uri, hash_including(persist: false)).and_return(remote_actor)
  end

  it "stores a valid signed activity and enqueues processing after admission" do
    expect { admission.call! }
      .to change(FederationInboxItem, :count).by(1)
      .and have_enqueued_job(Federation::ProcessInboxItemJob)

    item = FederationInboxItem.last
    expect(item).to be_pending
    expect(item.raw).to eq(activity)
    expect(item.raw_body_digest).to eq(headers.fetch("digest"))
    expect(item.remote_domain).to eq("remote.example")
  end

  it "admits a personal-inbox activity that directly addresses the recipient" do
    create_activity = {
      "id" => "https://remote.example/api/v1/trail/abc/activities/create-personal",
      "type" => "Create",
      "actor" => actor_uri,
      "object" => {
        "id" => "https://remote.example/api/v1/trail/abc",
        "type" => "Note",
        "attributedTo" => actor_uri
      },
      "to" => [ recipient.uri ],
      "cc" => []
    }
    personal = described_class.new(
      method: "POST", path:, content_type: Allure::Federation::MediaTypes::ACTIVITY_PUB,
      headers: signed_headers_for(create_activity), body: JSON.generate(create_activity),
      recipient_actor: recipient, actor_resolver:, verifier:
    )

    expect { personal.call! }.to change { recipient.inbox_items.count }.by(1)
  end

  # PLAN_REACTIONS.md §4.3: the object of a Like is the liked publication, not
  # a recipient URI. The old reading answered 404 to every HTTP-delivered Like
  # even though the processor understood it.
  it "admits a Like addressed to the publication author" do
    workout = create(:workout, user: recipient.user)
    publication = create(:workout_publication, workout:, actor: recipient)
    like = {
      "id" => "https://remote.example/activities/like-1",
      "type" => "Like",
      "actor" => actor_uri,
      "object" => publication.object_uri,
      "_allure_reaction" => "beer"
    }
    personal = described_class.new(
      method: "POST", path:, content_type: Allure::Federation::MediaTypes::ACTIVITY_PUB,
      headers: signed_headers_for(like), body: JSON.generate(like),
      recipient_actor: recipient, actor_resolver:, verifier:
    )

    expect { personal.call! }.to change { recipient.inbox_items.count }.by(1)
  end

  it "rejects a Like whose object is not a local publication" do
    like = {
      "id" => "https://remote.example/activities/like-2",
      "type" => "Like",
      "actor" => actor_uri,
      "object" => recipient.uri
    }
    personal = described_class.new(
      method: "POST", path:, content_type: Allure::Federation::MediaTypes::ACTIVITY_PUB,
      headers: signed_headers_for(like), body: JSON.generate(like),
      recipient_actor: recipient, actor_resolver:, verifier:
    )

    expect { personal.call! }.to raise_error(described_class::UnknownRecipient)
  end

  it "rejects a personal-inbox activity that addresses another local actor" do
    other = create(:local_actor)
    create_activity = {
      "id" => "https://remote.example/api/v1/trail/abc/activities/create-other",
      "type" => "Create",
      "actor" => actor_uri,
      "object" => {
        "id" => "https://remote.example/api/v1/trail/abc",
        "type" => "Note",
        "attributedTo" => actor_uri
      },
      "to" => [ other.uri ],
      "cc" => []
    }
    personal = described_class.new(
      method: "POST", path:, content_type: Allure::Federation::MediaTypes::ACTIVITY_PUB,
      headers: signed_headers_for(create_activity), body: JSON.generate(create_activity),
      recipient_actor: recipient, actor_resolver:, verifier:
    )

    expect { personal.call! }.to raise_error(described_class::UnknownRecipient)
    expect(FederationInboxItem.count).to eq(0)
  end

  describe "the signer's key" do
    it "verifies with the cached key however old, without fetching the actor" do
      remote_actor.update!(last_fetched_at: 3.days.ago)

      expect { admission.call! }.to change(FederationInboxItem, :count).by(1)
      expect(actor_resolver).not_to have_received(:resolve)
    end

    # A reset peer recreates its accounts with new keys under the same URIs.
    it "refreshes the actor once when the cached key no longer verifies" do
      new_key = OpenSSL::PKey::RSA.generate(2048)
      rotated = Actor.find(remote_actor.id).tap { |actor| actor.public_key_pem = new_key.public_key.to_pem }
      allow(actor_resolver).to receive(:resolve).with(actor_uri, refresh: true, persist: false).and_return(rotated)
      rotated_admission = described_class.new(
        method: "POST", path:, content_type: Allure::Federation::MediaTypes::ACTIVITY_PUB,
        headers: signed_headers_for(activity, key: new_key), body:, recipient_actor: recipient,
        actor_resolver:, verifier:
      )

      expect { rotated_admission.call! }.to change(FederationInboxItem, :count).by(1)
      expect(remote_actor.reload.public_key_pem).to eq(new_key.public_key.to_pem)
    end

    describe "bounding the fetch an unverified request causes (docs/dev/FEDERATION.md)" do
      let(:forger_key) { OpenSSL::PKey::RSA.generate(2048) }

      def forged_admission
        described_class.new(
          method: "POST", path:, content_type: Allure::Federation::MediaTypes::ACTIVITY_PUB,
          headers: signed_headers_for(activity, key: forger_key), body:, recipient_actor: recipient,
          actor_resolver:, verifier:
        )
      end

      around do |example|
        Federation::Safety::ResolutionAttempts.store = ActiveSupport::Cache::MemoryStore.new
        example.run
      ensure
        Federation::Safety::ResolutionAttempts.store = nil
      end

      before do
        allow(actor_resolver).to receive(:resolve).with(actor_uri, refresh: true, persist: false).and_return(remote_actor)
      end

      it "does not fetch again an actor fetched moments ago" do
        remote_actor.update!(last_fetched_at: 1.minute.ago)

        expect { forged_admission.call! }.to raise_error(described_class::InvalidRequest)
        expect(actor_resolver).not_to have_received(:resolve)
      end

      it "fetches a forged signer once, then asks for a retry without fetching it again" do
        expect { forged_admission.call! }.to raise_error(described_class::InvalidRequest)
        expect { forged_admission.call! }.to raise_error(described_class::Unavailable)
        expect { forged_admission.call! }.to raise_error(described_class::Unavailable)

        expect(actor_resolver).to have_received(:resolve).once
        expect(FederationInboxItem.count).to eq(0)
      end

      it "still admits the signer's own requests verified by the cached key" do
        expect { forged_admission.call! }.to raise_error(described_class::InvalidRequest)
        expect { admission.call! }.to change(FederationInboxItem, :count).by(1)
      end

      it "asks for a retry without fetching while another request is fetching" do
        semaphore = Federation::Safety::ResolutionGate::SEMAPHORE
        semaphore.acquire(Federation::Safety::ResolutionGate::SLOTS)
        begin
          expect { forged_admission.call! }.to raise_error(described_class::Unavailable, /busy/)
        ensure
          semaphore.release(Federation::Safety::ResolutionGate::SLOTS)
        end
        expect(actor_resolver).not_to have_received(:resolve)
        expect { admission.call! }.to change(FederationInboxItem, :count).by(1)
      end

      it "rate limits fetches per claimed authority even though none is admitted" do
        Federation::Safety::ResolutionAttempts::PER_AUTHORITY.times do |index|
          other = "https://remote.example/users/u#{index}"
          allow(actor_resolver).to receive(:resolve).with(other, persist: false)
            .and_raise(Federation::ActorResolver::FetchError, "404")
          document = activity.merge("actor" => other, "id" => "https://remote.example/activities/f#{index}")
          request = described_class.new(
            method: "POST", path:, content_type: Allure::Federation::MediaTypes::ACTIVITY_PUB,
            headers: signed_headers_for(document, key_id: "#{other}#main-key", key: forger_key),
            body: JSON.generate(document), recipient_actor: recipient, actor_resolver:, verifier:
          )
          expect { request.call! }.to raise_error(described_class::InvalidRequest)
        end

        expect { forged_admission.call! }.to raise_error(described_class::RateLimited)
        expect(actor_resolver).not_to have_received(:resolve).with(actor_uri, refresh: true, persist: false)
      end
    end

    it "asks the sender to retry when its actor cannot be fetched right now" do
      unknown_activity = activity.merge("actor" => "https://slow.example/users/demo",
                                        "id" => "https://slow.example/activities/1")
      allow(actor_resolver).to receive(:resolve).with("https://slow.example/users/demo", persist: false)
        .and_raise(Federation::ActorResolver::Unavailable, "timeout")
      slow = described_class.new(
        method: "POST", path:, content_type: Allure::Federation::MediaTypes::ACTIVITY_PUB,
        headers: signed_headers_for(unknown_activity, key_id: "https://slow.example/users/demo#main-key"),
        body: JSON.generate(unknown_activity), recipient_actor: recipient, actor_resolver:, verifier:
      )

      expect { slow.call! }.to raise_error(described_class::Unavailable)
    end

    # The account's actor answers 410 and its key cannot be fetched; nothing
    # here could be taken back anyway.
    it "acknowledges an unknown account's own deletion without fetching or storing" do
      gone_uri = "https://gone.example/users/old"
      deletion = { "id" => "#{gone_uri}#delete", "type" => "Delete", "actor" => gone_uri, "object" => gone_uri }
      gone = described_class.new(
        method: "POST", path: "/inbox", content_type: Allure::Federation::MediaTypes::ACTIVITY_PUB,
        headers: signed_headers_for(deletion, key_id: "#{gone_uri}#main-key"), body: JSON.generate(deletion),
        actor_resolver:, verifier:
      )

      expect(gone.call!.items).to be_empty
      expect(actor_resolver).not_to have_received(:resolve)
      expect(FederationInboxItem.count).to eq(0)
      expect(Actor.where(uri: gone_uri)).not_to exist
    end
  end

  it "makes duplicate valid admission idempotent" do
    admission.call!
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    result = admission.call!

    expect(result).to be_duplicate
    expect(FederationInboxItem.count).to eq(1)
    expect(ActiveJob::Base.queue_adapter.enqueued_jobs).to be_empty
  end

  it "rejects a conflicting body for an already admitted activity URI" do
    admission.call!
    conflicting_body = JSON.generate(activity.merge("object" => "https://allure.test/users/other"))
    conflicting = described_class.new(
      method: "POST", path:, content_type: Allure::Federation::MediaTypes::ACTIVITY_PUB,
      headers: headers.merge("Digest" => "SHA-256=#{Base64.strict_encode64(Digest::SHA256.digest(conflicting_body.b))}"),
      body: conflicting_body, recipient_actor: recipient, actor_resolver:, verifier:
    )

    expect { conflicting.call! }.to raise_error(described_class::InvalidRequest)
  end

  # Allure's activity URIs are deterministic (Federation::Outbox::EventBuilder)
  # and `(recipient, activity_uri)` is the idempotency key, so an activity
  # admitted under the URI a peer's future Delete will carry would turn that
  # Delete into the "conflicting body" refusal above — a permanent 401 and a
  # withdrawal that never lands. The id must live on the signer's own
  # authority (docs/dev/FEDERATION.md).
  context "when an activity id lives on another authority than its actor" do
    let(:peer_uri) { "https://peer.example/users/bob" }
    let(:peer_key) { OpenSSL::PKey::RSA.generate(2048) }
    let(:peer_actor) do
      create(
        :actor,
        uri: peer_uri,
        public_key_id: "#{peer_uri}#main-key",
        public_key_pem: peer_key.public_key.to_pem,
        inbox_url: "https://peer.example/users/bob/inbox"
      )
    end
    let(:object_uri) { "https://peer.example/api/v1/trail/abc" }
    let(:delete_uri) do
      Federation::Outbox::EventBuilder.activity_uri_for(
        object_uri:, activity_type: "Delete", idempotency_key: "publication:delete:#{object_uri}"
      )
    end
    let(:squat) { activity.merge("id" => delete_uri) }
    let(:delete) do
      {
        "id" => delete_uri,
        "type" => "Delete",
        "actor" => peer_uri,
        "object" => { "id" => object_uri, "type" => "Tombstone" },
        "to" => [ recipient.uri ],
        "cc" => []
      }
    end

    before do
      allow(actor_resolver).to receive(:resolve).with(peer_uri, persist: false).and_return(peer_actor)
    end

    it "refuses the squat without an inbox row and still admits the peer's own Delete under that URI" do
      squatting = described_class.new(
        method: "POST", path:, content_type: Allure::Federation::MediaTypes::ACTIVITY_PUB,
        headers: signed_headers_for(squat), body: JSON.generate(squat),
        recipient_actor: recipient, actor_resolver:, verifier:
      )

      expect { squatting.call! }
        .to raise_error(described_class::InvalidRequest, "activity id authority does not match the actor")
      expect(FederationInboxItem.count).to eq(0)

      withdrawal = described_class.new(
        method: "POST", path:, content_type: Allure::Federation::MediaTypes::ACTIVITY_PUB,
        headers: signed_headers_for(delete, key_id: peer_actor.public_key_id, key: peer_key),
        body: JSON.generate(delete), recipient_actor: recipient, actor_resolver:, verifier:
      )

      expect { withdrawal.call! }.to change { recipient.inbox_items.count }.by(1)
      expect(recipient.inbox_items.last)
        .to have_attributes(activity_uri: delete_uri, actor_uri: peer_uri, activity_type: "Delete")
    end
  end

  it "rejects an invalid signature without creating an inbox row" do
    invalid = described_class.new(
      method: "POST", path:, content_type: Allure::Federation::MediaTypes::ACTIVITY_PUB,
      headers: headers.merge("Signature" => "invalid"), body:, recipient_actor: recipient,
      actor_resolver:, verifier:
    )

    expect { invalid.call! }.to raise_error(described_class::InvalidRequest)
    expect(FederationInboxItem.count).to eq(0)
    expect(actor_resolver).not_to have_received(:resolve)
  end

  context "when the actor is seen for the first time" do
    # A distinct authority: the top-level stub already creates `remote_actor`,
    # and this row must not exist before the request under test.
    let(:fresh_uri) { "https://fresh.example/users/newcomer" }
    let(:unsaved_actor) do
      Actor.new(
        local: false, uri: fresh_uri, capability_profile: "unknown",
        public_key_id: "#{fresh_uri}#main-key", public_key_pem: remote_key.public_key.to_pem,
        inbox_url: "https://fresh.example/users/newcomer/inbox", last_fetched_at: now
      )
    end
    let(:activity) do
      {
        "id" => "https://fresh.example/activities/follow-1",
        "type" => "Follow",
        "actor" => fresh_uri,
        "object" => recipient.uri
      }
    end
    let(:headers) { signed_headers_for(activity, key_id: unsaved_actor.public_key_id) }

    before do
      allow(actor_resolver).to receive(:resolve).with(fresh_uri, persist: false).and_return(unsaved_actor)
    end

    it "persists the actor only once its signature verifies" do
      expect { admission.call! }.to change(Actor.remote, :count).by(1)

      expect(Actor.find_by(uri: fresh_uri)).to be_persisted
      expect(FederationInboxItem.last.actor_uri).to eq(fresh_uri)
    end

    it "leaves no actor row behind when the signature does not verify" do
      forged = headers.fetch("Signature").sub(/signature="[^"]+"/, %(signature="#{Base64.strict_encode64("x" * 256)}"))
      invalid = described_class.new(
        method: "POST", path:, content_type: Allure::Federation::MediaTypes::ACTIVITY_PUB,
        headers: headers.merge("Signature" => forged), body:, recipient_actor: recipient,
        actor_resolver:, verifier:
      )

      expect { invalid.call! }.to raise_error(described_class::InvalidRequest)
      expect(Actor.find_by(uri: fresh_uri)).to be_nil
      expect(FederationInboxItem.count).to eq(0)
    end
  end

  it "resolves a shared inbox recipient from a Follow target" do
    shared = described_class.new(
      method: "POST", path:, content_type: Allure::Federation::MediaTypes::ACTIVITY_PUB,
      headers:, body:, actor_resolver:, verifier:
    )

    expect { shared.call! }.to change { recipient.inbox_items.count }.by(1)
  end

  it "resolves an Accept recipient from the local follower actor" do
    following = create(
      :following,
      follower_actor: recipient,
      followed_actor: remote_actor,
      uri: "http://allure.test:3000/activities/follow-outbound"
    )
    accept = {
      "id" => "https://remote.example/activities/accept-1",
      "type" => "Accept",
      "actor" => remote_actor.uri,
      "object" => following.uri
    }
    accept_body = JSON.generate(accept)
    accept_admission = described_class.new(
      method: "POST", path:, content_type: Allure::Federation::MediaTypes::ACTIVITY_PUB,
      headers: signed_headers_for(accept), body: accept_body, actor_resolver:, verifier:
    )

    expect { accept_admission.call! }.to change { recipient.inbox_items.count }.by(1)
  end

  # docs/dev/FEDERATION.md: an Accept or Undo naming a row the sender is not party to
  # answers exactly like one naming an unknown URI, so no signer can test who
  # follows or reacted to whom.
  describe "keeping the social graph hidden" do
    let(:other_remote) { create(:actor, uri: "https://honest.example/users/bob") }

    def outcome_for(document)
      described_class.new(
        method: "POST", path:, content_type: Allure::Federation::MediaTypes::ACTIVITY_PUB,
        headers: signed_headers_for(document), body: JSON.generate(document), actor_resolver:, verifier:
      ).call!
      :admitted
    rescue described_class::UnknownRecipient
      :unknown_recipient
    end

    def probe(type, object, index)
      { "id" => "https://remote.example/activities/probe-#{index}", "type" => type, "actor" => actor_uri, "object" => object }
    end

    it "answers an Accept for someone else's follow like one for an unknown URI" do
      foreign = create(:following, follower_actor: recipient, followed_actor: other_remote,
                                   uri: "http://allure.test:3000/activities/follow-to-bob")

      expect(outcome_for(probe("Accept", foreign.uri, 1))).to eq(outcome_for(probe("Accept", "http://allure.test:3000/activities/none", 2)))
      expect(outcome_for(probe("Accept", foreign.uri, 3))).to eq(:unknown_recipient)
      expect(FederationInboxItem.count).to eq(0)
    end

    it "answers an Undo of someone else's follow or reaction like one for an unknown URI" do
      follow = create(:following, follower_actor: other_remote, followed_actor: recipient,
                                  uri: "https://honest.example/activities/follow-1")
      workout = create(:workout, user: recipient.user)
      reaction = create(:reaction, actor: other_remote, workout:, uri: "https://honest.example/activities/like-1")

      expect(outcome_for(probe("Undo", follow.uri, 1))).to eq(:unknown_recipient)
      expect(outcome_for(probe("Undo", reaction.uri, 2))).to eq(:unknown_recipient)
      expect(outcome_for(probe("Undo", "https://honest.example/activities/none", 3))).to eq(:unknown_recipient)
      expect(FederationInboxItem.count).to eq(0)
    end

    it "still routes an Undo of the sender's own follow and reaction" do
      follow = create(:following, follower_actor: remote_actor, followed_actor: recipient,
                                  uri: "https://remote.example/activities/follow-own")
      workout = create(:workout, user: recipient.user)
      reaction = create(:reaction, actor: remote_actor, workout:, uri: "https://remote.example/activities/like-own")

      expect(outcome_for(probe("Undo", follow.uri, 1))).to eq(:admitted)
      expect(outcome_for(probe("Undo", { "id" => reaction.uri, "type" => "Like" }, 2))).to eq(:admitted)
      expect(recipient.inbox_items.count).to eq(2)
    end
  end

  # A delivered publication addresses the sender's own audience and never names
  # a recipient on this instance, so a shared inbox has to derive its recipients
  # from accepted follows. This is the exact case the Tier-2 ring exercises.
  describe "a publication addressed to the sender's audience" do
    let(:create_activity) do
      {
        "id" => "https://remote.example/api/v1/trail/abc/activities/create-1",
        "type" => "Create",
        "actor" => actor_uri,
        "object" => {
          "id" => "https://remote.example/api/v1/trail/abc",
          "type" => "Note",
          "attributedTo" => actor_uri
        },
        "to" => [ described_class::PUBLIC_AUDIENCE ],
        "cc" => [ "https://remote.example/users/demo/followers" ]
      }
    end

    # The signature covers (request-target), so the canonical path has to be the
    # shared inbox rather than the personal one.
    let(:path) { "/inbox" }

    def shared_admission_for(document)
      described_class.new(
        method: "POST", path:, content_type: Allure::Federation::MediaTypes::ACTIVITY_PUB,
        headers: signed_headers_for(document), body: JSON.generate(document),
        actor_resolver:, verifier:
      )
    end

    it "admits an actor Delete that names a local actor in the explicit recipients list" do
      actor_delete = {
        "id" => "https://remote.example/activities/delete-actor-1",
        "type" => "Delete",
        "actor" => actor_uri,
        "object" => { "id" => actor_uri, "type" => "Tombstone" },
        "recipients" => [ recipient.uri ],
        "to" => [ "#{actor_uri}/followers" ],
        "cc" => []
      }

      expect { shared_admission_for(actor_delete).call! }
        .to change { recipient.inbox_items.count }.by(1)
    end

    it "admits one row per local accepted follower of the sender" do
      create(:following, :accepted, follower_actor: recipient, followed_actor: remote_actor)

      expect { shared_admission_for(create_activity).call! }
        .to change { recipient.inbox_items.count }.by(1)
    end

    it "does not admit a row for a local actor that does not follow the sender" do
      expect { shared_admission_for(create_activity).call! }
        .to raise_error(described_class::UnknownRecipient)
      expect(FederationInboxItem.count).to eq(0)
    end

    it "does not admit a row for a pending follow" do
      create(:following, follower_actor: recipient, followed_actor: remote_actor)

      expect { shared_admission_for(create_activity).call! }
        .to raise_error(described_class::UnknownRecipient)
    end

    it "admits a withdrawal addressed straight at a local actor" do
      delete_activity = {
        "id" => "https://remote.example/api/v1/trail/abc/activities/delete-1",
        "type" => "Delete",
        "actor" => actor_uri,
        "object" => "https://remote.example/api/v1/trail/abc",
        "to" => [ recipient.uri ],
        "cc" => []
      }

      expect { shared_admission_for(delete_activity).call! }
        .to change { recipient.inbox_items.count }.by(1)
    end

    it "accepts an audience naming the sender's own followers collection" do
      remote_actor.update!(raw: { "followers" => "https://remote.example/users/demo/followers" })
      create(:following, :accepted, follower_actor: recipient, followed_actor: remote_actor)
      followers_only = create_activity.merge(
        "to" => [ "https://remote.example/users/demo/followers" ], "cc" => []
      )

      expect { shared_admission_for(followers_only).call! }
        .to change { recipient.inbox_items.count }.by(1)
    end
  end

  describe "the safety gate" do
    it "refuses a blocked actor before resolving it" do
      create(:federation_actor_block, actor_uri:)

      expect { admission.call! }.to raise_error(described_class::Blocked)
      expect(FederationInboxItem.count).to eq(0)
    end

    it "refuses a blocked authority" do
      create(:federation_domain_block, domain: "remote.example")

      expect { admission.call! }.to raise_error(described_class::Blocked)
    end

    it "refuses an authority whose parent domain is blocked" do
      create(:federation_domain_block, domain: "example")

      expect { admission.call! }.to raise_error(described_class::Blocked)
      expect(actor_resolver).not_to have_received(:resolve)
    end

    it "rate limits the authority once the minute is full" do
      60.times { create(:federation_inbox_item, remote_domain: "remote.example", recipient_actor: recipient) }

      expect { admission.call! }.to raise_error(described_class::RateLimited) { |error|
        expect(error.retry_after).to be_between(1, 60)
      }
      expect(FederationInboxItem.count).to eq(60)
    end

    # A host is case-insensitive: a peer must not earn a fresh minute by
    # rotating the case of its actor URI.
    it "rate limits a case-variant authority against the same bucket" do
      60.times { create(:federation_inbox_item, remote_domain: "remote.example", recipient_actor: recipient) }
      upper_activity = activity.merge(
        "id" => "https://REMOTE.example/activities/follow-upper",
        "actor" => "https://REMOTE.example/users/demo"
      )
      upper = described_class.new(
        method: "POST", path:, content_type: Allure::Federation::MediaTypes::ACTIVITY_PUB,
        headers: signed_headers_for(upper_activity), body: JSON.generate(upper_activity),
        recipient_actor: recipient, actor_resolver:, verifier:
      )

      expect { upper.call! }.to raise_error(described_class::RateLimited)
    end
  end
end
