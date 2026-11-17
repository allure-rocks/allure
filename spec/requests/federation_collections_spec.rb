# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Slice 5 federation collections", type: :request do
  let(:user) { create(:user, username: "marie") }
  let(:activity_accept) { { "Accept" => Allure::Federation::MediaTypes::ACTIVITY_PUB } }

  before { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }
  after { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }

  it "does not enumerate followers or following publicly" do
    owner_actor = Federation::ActorProvisioner.new(user:).call!
    remote = create(:actor)
    create(:following, :accepted, follower_actor: remote, followed_actor: owner_actor)
    create(:following, :accepted, follower_actor: owner_actor, followed_actor: remote)

    get "/users/marie/followers", headers: activity_accept
    expect(JSON.parse(response.body)).to include("totalItems" => 0)

    get "/users/marie/following", headers: activity_accept
    expect(JSON.parse(response.body)).to include("totalItems" => 0)

    get "/users/marie/followers", params: { page: 1 }, headers: activity_accept
    expect(JSON.parse(response.body).fetch("orderedItems")).to eq([])
  end

  it "excludes deleted publication Creates from the outbox" do
    workout = create(:workout, user:)
    create(:track_segment, workout:)
    profile = create(:publishing_profile, :without_endpoint_masks, user:)
    publication = publish_workout!(user:, workout:, profile:)
    publication.mark_deleted!

    get "/users/marie/outbox", params: { page: 1 }, headers: activity_accept
    page = JSON.parse(response.body)

    expect(page.fetch("totalItems")).to eq(0)
    expect(page.fetch("orderedItems")).to eq([])
  end

  # docs/dev/COMMENTS.md: a comment's Create leaves the outbox with its
  # comment.
  it "lists the owner's public comment and drops it once deleted" do
    workout = create(:workout, user:)
    create(:workout_publication, workout:, publishing_profile: public_publishing_profile_for(user))
    comment = Comments::Post.new(user:, target: workout, body: "Merci à tous").call!

    get "/users/marie/outbox", params: { page: 1 }, headers: activity_accept
    expect(JSON.parse(response.body).fetch("orderedItems").map { |item| item.dig("object", "id") }).to include(comment.uri)

    Comments::Delete.new(user:, comment:).call!

    get "/users/marie/outbox", params: { page: 1 }, headers: activity_accept
    page = JSON.parse(response.body)
    expect(page.fetch("orderedItems").map { |item| item["type"] }).not_to include("Create")
    expect(response.body).not_to include("Merci à tous")
  end

  # docs/dev/COMMENTS.md: the host's relay leaves the outbox with the comment.
  it "lists the relay of a member's comment and drops it once the comment leaves" do
    workout = create(:workout, user:)
    create(:workout_publication, workout:, publishing_profile: public_publishing_profile_for(user))
    member = create(:user)
    comment = Comments::Post.new(user: member, target: workout, body: "Quelle vue").call!

    get "/users/marie/outbox", params: { page: 1 }, headers: activity_accept
    announce = JSON.parse(response.body).fetch("orderedItems").find { |item| item["type"] == "Announce" }
    expect(announce.dig("object", "id")).to eq(comment.uri)

    Comments::Delete.new(user: member, comment:).call!

    get "/users/marie/outbox", params: { page: 1 }, headers: activity_accept
    expect(JSON.parse(response.body).fetch("orderedItems").map { |item| item["type"] }).not_to include("Announce")
    expect(response.body).not_to include("Quelle vue")
  end

  it "exposes Delete only to its immutable recipients" do
    workout = create(:workout, user:)
    create(:track_segment, workout:)
    profile = create(:publishing_profile, :without_endpoint_masks, user:)
    publication = publish_workout!(user:, workout:, profile:)
    owner_actor = user.reload.actor
    recipient = create(
      :actor,
      uri: "https://remote.example/users/recipient",
      inbox_url: "https://remote.example/inbox",
      public_key_id: "https://remote.example/users/recipient#main-key",
      public_key_pem: OpenSSL::PKey::RSA.generate(2048).public_key.to_pem
    )
    stranger = create(
      :actor,
      uri: "https://remote.example/users/stranger",
      inbox_url: "https://remote.example/inbox",
      public_key_id: "https://remote.example/users/stranger#main-key",
      public_key_pem: OpenSSL::PKey::RSA.generate(2048).public_key.to_pem
    )
    create(:following, :accepted, follower_actor: recipient, followed_actor: owner_actor)
    create(:following, :accepted, follower_actor: stranger, followed_actor: owner_actor)
    create_event = FederationOutboxEvent.find_by!(activity_type: "Create")
    delivery = FederationDelivery.create!(
      outbox_event: create_event,
      inbox_url: "https://remote.example/inbox-#{SecureRandom.hex(4)}",
      status: "delivered"
    )
    FederationDeliveryRecipient.create!(delivery:, actor_uri: recipient.uri, status: "authorized")
    elsewhere = create(:actor, uri: "https://elsewhere.example/users/eve", inbox_url: "https://elsewhere.example/inbox")
    create(:following, :accepted, follower_actor: elsewhere, followed_actor: owner_actor)
    FederationDeliveryRecipient.create!(delivery:, actor_uri: elsewhere.uri, status: "authorized")
    Workouts::PublicationWithdrawal.new(user:, workout:).call!

    serializer_for = ->(viewer) do
      Federation::Serializers::OrderedCollection.new(
        actor: owner_actor, collection: "outbox", viewer_actor: viewer, page: 1
      ).page
    end

    recipient_page = serializer_for.call(recipient)
    stranger_page = serializer_for.call(stranger)

    expect(recipient_page.fetch("orderedItems").map { |item| item["type"] }).to include("Delete")
    expect(stranger_page.fetch("orderedItems").map { |item| item["type"] }).not_to include("Delete")
    # docs/dev/FEDERATION.md: the Delete names its recipients, and each reader sees
    # only those of its own authority.
    delete_for_recipient = recipient_page.fetch("orderedItems").find { |item| item["type"] == "Delete" }
    expect(delete_for_recipient.fetch("to")).to eq([ recipient.uri ])
    elsewhere_page = serializer_for.call(elsewhere)
    delete_for_elsewhere = elsewhere_page.fetch("orderedItems").find { |item| item["type"] == "Delete" }
    expect(delete_for_elsewhere.fetch("to")).to eq([ elsewhere.uri ])
  end

  it "bounds outbox pages" do
    provisioned = Federation::ActorProvisioner.new(user:).call!
    25.times do |index|
      target = create(:actor, uri: "https://remote.example/users/target-#{index}")
      Federation::Outbox::EventBuilder.new(
        actor: provisioned,
        subject_type: "Actor",
        subject_id: provisioned.id,
        activity_type: "Like",
        object_uri: provisioned.uri,
        idempotency_key: "test:paging:#{index}",
        payload: { "type" => "Like", "actor" => provisioned.uri, "object" => target.uri },
        audience: { "to" => [ "https://www.w3.org/ns/activitystreams#Public" ], "cc" => [] }
      ).call!
    end

    get "/users/marie/outbox", params: { page: 1 }, headers: activity_accept
    first = JSON.parse(response.body)

    get "/users/marie/outbox", params: { page: 2 }, headers: activity_accept
    second = JSON.parse(response.body)

    expect(first.fetch("totalItems")).to eq(25)
    expect(first.fetch("orderedItems").length).to eq(20)
    expect(second.fetch("orderedItems").length).to eq(5)
  end

  # docs/dev/FEDERATION.md: a signed GET never fetches nor stores an actor this
  # instance does not know. Only a known actor can be addressed by an outbox
  # item or hold a follow, so an unknown signer reads what anonymous readers
  # read.
  describe "a signed outbox read" do
    let(:owner_actor) { Federation::ActorProvisioner.new(user:).call! }
    let(:known_key) { OpenSSL::PKey::RSA.generate(2048) }
    let(:known) do
      create(:actor, uri: "https://remote.example/users/known", inbox_url: "https://remote.example/inbox",
                     public_key_id: "https://remote.example/users/known#main-key",
                     public_key_pem: known_key.public_key.to_pem)
    end
    let(:actor_resolver) { instance_double(Federation::ActorResolver) }

    def signed_get_headers(key:, key_id:, path: "/users/marie/outbox")
      values = {
        "host" => "www.example.com",
        "date" => Time.now.utc.httpdate,
        "digest" => "SHA-256=#{Base64.strict_encode64(Digest::SHA256.digest(""))}"
      }
      signed_headers = %w[(request-target) host date digest]
      canonical = Allure::Federation::Signature::CanonicalRequest.new(
        method: "GET", path:, headers: values, signed_headers:
      ).call
      signature = Base64.strict_encode64(key.sign(OpenSSL::Digest::SHA256.new, canonical))
      activity_accept.merge(
        "HTTP_HOST" => values.fetch("host"),
        "HTTP_DATE" => values.fetch("date"),
        "HTTP_DIGEST" => values.fetch("digest"),
        "HTTP_SIGNATURE" => %(keyId="#{key_id}",algorithm="rsa-sha256",headers="#{signed_headers.join(" ")}",signature="#{signature}")
      )
    end

    def direct_event_for(actor)
      Federation::Outbox::EventBuilder.new(
        actor: owner_actor, subject_type: "Actor", subject_id: owner_actor.id, activity_type: "Like",
        object_uri: owner_actor.uri, idempotency_key: "test:direct:#{actor.uri}",
        payload: { "type" => "Like", "actor" => owner_actor.uri, "object" => actor.uri },
        audience: { "to" => [ actor.uri ], "cc" => [] }
      ).call!
    end

    def total_items = JSON.parse(response.body).fetch("totalItems")

    before do
      allow(actor_resolver).to receive(:resolve)
      allow(Federation::ActorResolver).to receive(:new).and_return(actor_resolver)
      direct_event_for(known)
    end

    it "serves an unknown signer the public outbox without fetching or storing it" do
      stranger_key = OpenSSL::PKey::RSA.generate(2048)

      expect {
        get "/users/marie/outbox",
            headers: signed_get_headers(key: stranger_key, key_id: "https://attacker.example/users/x1#main-key")
      }.not_to change(Actor, :count)

      expect(response).to have_http_status(:ok)
      expect(total_items).to eq(0)
      expect(actor_resolver).not_to have_received(:resolve)
    end

    it "shows a known signer the items addressed to it" do
      get "/users/marie/outbox", headers: signed_get_headers(key: known_key, key_id: known.public_key_id)

      expect(response).to have_http_status(:ok)
      expect(total_items).to eq(1)
      expect(actor_resolver).not_to have_received(:resolve)
    end

    it "does not store a known actor's refreshed document when the signature still fails" do
      forger_key = OpenSSL::PKey::RSA.generate(2048)
      refreshed = Actor.find(known.id).tap { |actor| actor.display_name = "Refreshed" }
      allow(actor_resolver).to receive(:resolve).with(known.uri, refresh: true, persist: false).and_return(refreshed)

      get "/users/marie/outbox", headers: signed_get_headers(key: forger_key, key_id: known.public_key_id)

      expect(response).to have_http_status(:ok)
      expect(total_items).to eq(0)
      expect(known.reload.display_name).to be_nil
    end

    it "stores a known actor's rotated key once it verifies the request" do
      rotated_key = OpenSSL::PKey::RSA.generate(2048)
      refreshed = Actor.find(known.id).tap { |actor| actor.public_key_pem = rotated_key.public_key.to_pem }
      allow(actor_resolver).to receive(:resolve).with(known.uri, refresh: true, persist: false).and_return(refreshed)

      get "/users/marie/outbox", headers: signed_get_headers(key: rotated_key, key_id: known.public_key_id)

      expect(total_items).to eq(1)
      expect(known.reload.public_key_pem).to eq(rotated_key.public_key.to_pem)
    end
  end
end
