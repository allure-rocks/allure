# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Federation publication protocol", type: :request do
  let(:owner) { create(:user) }
  let(:public_workout) { create(:workout, user: owner, title: "Public route") }
  let!(:public_track_segment) { create(:track_segment, workout: public_workout) }
  let(:public_publication) do
    profile = create(:publishing_profile, :without_endpoint_masks, user: owner)
    publish_workout!(user: owner, workout: public_workout, profile:)
  end
  let(:followers_workout) { create(:workout, user: owner, title: "Followers route") }
  let!(:followers_track_segment) { create(:track_segment, workout: followers_workout) }
  let(:followers_publication) do
    profile = create(:publishing_profile, :followers, :without_endpoint_masks, user: owner)
    Federation::ActorProvisioner.new(user: owner).call!
    create(:workout_publication, workout: followers_workout, publishing_profile: profile)
  end
  let(:remote_key) { OpenSSL::PKey::RSA.generate(2048) }
  let(:remote_actor) do
    create(
      :actor,
      uri: "https://remote.example/users/follower",
      public_key_id: "https://remote.example/users/follower#main-key",
      public_key_pem: remote_key.public_key.to_pem
    )
  end
  let(:actor_resolver) { instance_double(Federation::ActorResolver) }

  before do
    owner.reload
    allow(actor_resolver).to receive(:resolve).with(remote_actor.uri).and_return(remote_actor)
    allow(Federation::ActorResolver).to receive(:new).and_return(actor_resolver)
  end

  def signed_get_headers(path:)
    values = {
      "host" => "www.example.com",
      "date" => Time.now.utc.httpdate,
      "digest" => "SHA-256=47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU="
    }
    signed_headers = %w[(request-target) host date digest]
    canonical = Allure::Federation::Signature::CanonicalRequest.new(
      method: "GET", path:, headers: values, signed_headers:
    ).call
    signature = remote_key.sign(OpenSSL::Digest::SHA256.new, canonical)

    {
      "HTTP_HOST" => values.fetch("host"),
      "HTTP_DATE" => values.fetch("date"),
      "HTTP_DIGEST" => values.fetch("digest"),
      "HTTP_SIGNATURE" => %(keyId="#{remote_actor.public_key_id}",algorithm="rsa-sha256",headers="#{signed_headers.join(" ")}",signature="#{Base64.strict_encode64(signature)}")
    }
  end

  it "serves a public Note anonymously" do
    publication = public_publication

    get workout_publication_path(publication)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq(Allure::Federation::MediaTypes::ACTIVITY_PUB)
    expect(JSON.parse(response.body)).to include(
      "id" => publication.object_uri,
      "type" => "Note",
      "name" => "Public route"
    )
  end

  it "returns 404 for followers-only Notes even to a verified accepted actor during M4.5" do
    publication = followers_publication
    create(:following, :accepted, follower_actor: remote_actor, followed_actor: owner.reload.actor)
    path = workout_publication_path(publication)

    get path
    expect(response).to have_http_status(:not_found)

    get path, headers: signed_get_headers(path:)
    expect(response).to have_http_status(:not_found)
  end

  it "returns 404 for followers-only media even to a verified accepted actor during M4.5" do
    profile = create(
      :publishing_profile,
      :followers,
      :without_endpoint_masks,
      user: owner,
      settings: PublishingProfile::DEFAULT_SETTINGS.merge(
        "gpx" => true, "mask_start" => false, "mask_finish" => false
      )
    )
    workout = create(:workout, user: owner)
    create(:track_segment, workout:)
    Federation::ActorProvisioner.new(user: owner).call!
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("gpx"),
      filename: "route.gpx",
      content_type: "application/gpx+xml"
    )
    publication = create(
      :workout_publication,
      workout:,
      publishing_profile: profile,
      sanitized_gpx_blob_id: blob.id
    )
    publication.gpx.attach(blob)
    create(:following, :accepted, follower_actor: remote_actor, followed_actor: owner.reload.actor)
    path = workout_publication_gpx_path(publication)

    get path
    expect(response).to have_http_status(:not_found)

    get path, headers: signed_get_headers(path:)
    expect(response).to have_http_status(:not_found)
  end

  it "returns 404 for followers-only media even with a valid signature during M4.5" do
    publication = followers_publication
    create(:following, :accepted, follower_actor: remote_actor, followed_actor: owner.reload.actor)
    path = workout_publication_route_image_path(publication)

    get path, headers: signed_get_headers(path:)
    expect(response).to have_http_status(:not_found)

    get path, headers: signed_get_headers(path:).merge("HTTP_SIGNATURE" => "invalid")
    expect(response).to have_http_status(:not_found)
  end

  describe "with restricted federation enabled" do
    before do
      allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(true)
      Federation::ActorProvisioner.new(user: owner).call!
      remote_actor.update!(capability_profile: "restricted_fetch")
      create(:following, :accepted, follower_actor: remote_actor, followed_actor: owner.reload.actor)
    end

    it "serves a followers-only Note to the promoted accepted follower" do
      publication = followers_publication
      path = workout_publication_path(publication)

      get path
      expect(response).to have_http_status(:not_found)

      get path, headers: signed_get_headers(path:)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to include("id" => publication.object_uri)
    end

    it "treats an unknown signer as anonymous without fetching or storing it" do
      publication = followers_publication
      path = workout_publication_path(publication)
      headers = signed_get_headers(path:)
      headers["HTTP_SIGNATURE"] = headers["HTTP_SIGNATURE"]
        .sub(remote_actor.public_key_id, "https://attacker.example/users/x1#main-key")
      allow(actor_resolver).to receive(:resolve)

      expect { get path, headers: }.not_to change(Actor, :count)
      expect(response).to have_http_status(:not_found)
      expect(actor_resolver).not_to have_received(:resolve)
    end

    it "denies a followers-only Note to an unpromoted accepted follower" do
      remote_actor.update!(capability_profile: "public_only")
      publication = followers_publication
      path = workout_publication_path(publication)

      get path, headers: signed_get_headers(path:)
      expect(response).to have_http_status(:not_found)
    end

    it "serves followers-only media to the promoted accepted follower" do
      profile = create(
        :publishing_profile,
        :followers,
        :without_endpoint_masks,
        user: owner,
        settings: PublishingProfile::DEFAULT_SETTINGS.merge("gpx" => true)
      )
      workout = create(:workout, user: owner)
      create(:track_segment, workout:)
      Federation::ActorProvisioner.new(user: owner).call!
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("gpx"),
        filename: "route.gpx",
        content_type: "application/gpx+xml"
      )
      publication = create(
        :workout_publication,
        workout:,
        publishing_profile: profile,
        sanitized_gpx_blob_id: blob.id
      )
      publication.gpx.attach(blob)
      path = workout_publication_gpx_path(publication)

      get path, headers: signed_get_headers(path:)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/gpx+xml")
    end
  end
end
