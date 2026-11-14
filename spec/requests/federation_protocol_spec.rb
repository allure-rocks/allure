# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Federation read protocol", type: :request do
  let(:user) do
    create(
      :user,
      username: "marie",
      display_name: "Marie Dufour",
      bio: "<script>alert(1)</script><strong>Hiker</strong>"
    )
  end
  let(:activity_accept) { { "ACCEPT" => Allure::Federation::MediaTypes::ACTIVITY_PUB } }

  context "when federation is disabled" do
    around do |example|
      previous = ENV["FEDERATION_ENABLED"]
      ENV["FEDERATION_ENABLED"] = "false"
      example.run
    ensure
      previous.nil? ? ENV.delete("FEDERATION_ENABLED") : ENV["FEDERATION_ENABLED"] = previous
    end

    it "does not serve protocol endpoints" do
      get "/.well-known/nodeinfo"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "WebFinger" do
    it "discovers a local actor using the configured domain and port" do
      user
      get "/.well-known/webfinger",
          params: { resource: "acct:marie@allure.test:3001" },
          headers: { "ACCEPT" => Allure::Federation::MediaTypes::WEBFINGER }

      document = JSON.parse(response.body)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq(Allure::Federation::MediaTypes::WEBFINGER)
      expect(document).to include(
        "subject" => "acct:marie@allure.test:3001",
        "aliases" => [ "http://allure.test:3001/users/marie", "http://allure.test:3001/@marie" ]
      )
      expect(document.fetch("links")).to include(
        include(
          "rel" => "self",
          "type" => Allure::Federation::MediaTypes::ACTIVITY_PUB,
          "href" => "http://allure.test:3001/users/marie"
        )
      )
    end

    it "does not proxy remote or mismatched resources" do
      get "/.well-known/webfinger", params: { resource: "acct:remote@remote.example" }
      expect(response).to have_http_status(:not_found)

      get "/.well-known/webfinger", params: { resource: "acct:marie@allure.test" }
      expect(response).to have_http_status(:not_found)
    end

    it "does not discover a tombstoned actor" do
      actor = Federation::ActorProvisioner.new(user: user).call!
      actor.tombstone!

      get "/.well-known/webfinger", params: { resource: "acct:marie@allure.test:3001" }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "actor resource" do
    it "returns a sanitized Person without authentication" do
      user
      get "/users/marie", headers: activity_accept

      document = JSON.parse(response.body)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq(Allure::Federation::MediaTypes::ACTIVITY_PUB)
      expect(document).to include(
        "type" => "Person",
        "id" => "http://allure.test:3001/users/marie",
        "preferredUsername" => "marie",
        "name" => "Marie Dufour",
        "url" => "http://allure.test:3001/@marie",
        "inbox" => "http://allure.test:3001/users/marie/inbox",
        "outbox" => "http://allure.test:3001/users/marie/outbox",
        "followers" => "http://allure.test:3001/users/marie/followers",
        "following" => "http://allure.test:3001/users/marie/following"
      )
      expect(document.fetch("summary")).to eq("alert(1)Hiker")
      expect(document.fetch("publicKey")).to include(
        "id" => "http://allure.test:3001/users/marie#main-key",
        "owner" => "http://allure.test:3001/users/marie"
      )
      expect(document.to_json).not_to include(user.email_address)
      expect(document.to_json).not_to include("private_key_ciphertext")
    end

    it "redirects browser requests to the human profile" do
      user
      get "/users/marie", headers: { "ACCEPT" => "text/html" }

      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to("/@marie")
    end

    it "returns a tombstone with HTTP 410" do
      actor = Federation::ActorProvisioner.new(user: user).call!
      deleted_at = Time.utc(2026, 8, 26, 12)
      actor.tombstone!(at: deleted_at)

      get "/users/marie", headers: activity_accept

      expect(response).to have_http_status(:gone)
      expect(JSON.parse(response.body)).to eq(
        "@context" => "https://www.w3.org/ns/activitystreams",
        "id" => "http://allure.test:3001/users/marie",
        "type" => "Tombstone",
        "formerType" => "Person",
        "deleted" => "2026-08-26T12:00:00Z"
      )
    end

    it "serves the canonical actor for a differently cased path" do
      user
      get "/users/MARIE", headers: activity_accept

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).fetch("id")).to eq("http://allure.test:3001/users/marie")
    end
  end

  describe "human profile" do
    it "redirects an anonymous visitor and renders for a signed-in member" do
      user
      get "/@marie", headers: { "ACCEPT" => "text/html" }

      expect(response).to redirect_to(new_session_path)

      sign_in_as(create(:user))
      get "/@marie", headers: { "ACCEPT" => "text/html" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Marie Dufour", "@marie@allure.test:3001")
      expect(response.body).to include("application/activity+json")
    end
  end

  describe "NodeInfo" do
    it "publishes links for both supported schema versions" do
      get "/.well-known/nodeinfo"

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq(Allure::Federation::MediaTypes::NODE_INFO)
      expect(JSON.parse(response.body).fetch("links")).to eq([
        {
          "rel" => "http://nodeinfo.diaspora.software/ns/schema/2.1",
          "href" => "http://allure.test:3001/nodeinfo/2.1"
        },
        {
          "rel" => "http://nodeinfo.diaspora.software/ns/schema/2.2",
          "href" => "http://allure.test:3001/nodeinfo/2.2"
        }
      ])
    end

    it "reports public aggregate information without coordinates" do
      user
      get "/nodeinfo/2.2"

      expect(response).to have_http_status(:ok)
      document = JSON.parse(response.body)

      expect(document).to include(
        "version" => "2.2",
        "software" => { "name" => "allure", "version" => Allure::VERSION },
        "protocols" => [ "activitypub" ],
        "openRegistrations" => false
      )
      expect(document.dig("usage", "users", "total")).to eq(1)
      expect(document.to_json).not_to include("latitude", "longitude", "privacy")
    end

    it "publishes the configured instance metadata" do
      allow(Allure::Instance).to receive(:name).and_return("Mon serveur")
      allow(Allure::Instance).to receive(:description).and_return("Une instance auto-hébergée.")
      allow(Allure::Instance).to receive(:hosted_by?).and_return(true)
      allow(Allure::Instance).to receive(:host_name).and_return("Camille")
      allow(Allure::Instance).to receive(:host_url).and_return("https://example.org")

      get "/nodeinfo/2.2"

      expect(JSON.parse(response.body).fetch("metadata")).to eq(
        "nodeName" => "Mon serveur",
        "nodeDescription" => "Une instance auto-hébergée.",
        "host" => { "name" => "Camille", "url" => "https://example.org" }
      )
    end

    it "keeps the NodeInfo metadata minimal when nothing is configured" do
      allow(Allure::Instance).to receive(:description).and_return(nil)
      allow(Allure::Instance).to receive(:hosted_by?).and_return(false)

      get "/nodeinfo/2.2"

      expect(JSON.parse(response.body).fetch("metadata")).to eq("nodeName" => "Allure")
    end
  end

  describe "collections" do
    it "returns empty ordered collections and their pages" do
      actor = Federation::ActorProvisioner.new(user: user).call!

      get "/users/marie/outbox", headers: activity_accept
      collection = JSON.parse(response.body)

      expect(response).to have_http_status(:ok)
      expect(collection).to include(
        "id" => "#{actor.uri}/outbox",
        "type" => "OrderedCollection",
        "totalItems" => 0,
        "first" => "#{actor.uri}/outbox?page=1"
      )

      get "/users/marie/outbox", params: { page: 1 }, headers: activity_accept
      page = JSON.parse(response.body)

      expect(page).to include(
        "id" => "#{actor.uri}/outbox?page=1",
        "type" => "OrderedCollectionPage",
        "partOf" => "#{actor.uri}/outbox",
        "totalItems" => 0,
        "orderedItems" => []
      )
    end

    it "does not expose collections for unknown actors" do
      get "/users/unknown/followers", headers: activity_accept

      expect(response).to have_http_status(:not_found)
    end

    it "exposes active public activities through the actor outbox" do
      workout = create(:workout, user:)
      create(:track_segment, workout:)
      profile = create(:publishing_profile, :without_endpoint_masks, user:)
      publication = publish_workout!(user:, workout:, profile:)

      get "/users/marie/outbox", params: { page: 1 }, headers: activity_accept

      page = JSON.parse(response.body)
      expect(response).to have_http_status(:ok)
      expect(page.fetch("totalItems")).to eq(1)
      expect(page.fetch("orderedItems")).to include(
        include(
          "type" => "Create",
          "object" => include("id" => publication.object_uri, "type" => "Note")
        )
      )
    end
  end
end
