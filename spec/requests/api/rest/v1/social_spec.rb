# frozen_string_literal: true

require "rails_helper"

RSpec.describe "REST API social reads (docs/dev/API.md)", type: :request do
  let(:reader) { create(:user) }
  let(:author) { create(:user, email_address: "secret-author@example.com") }
  let(:headers) { api_headers_for(reader, scopes: %w[social:read]) }
  let(:reader_actor) { Federation::ActorProvisioner.new(user: reader).call! }
  let(:author_actor) { Federation::ActorProvisioner.new(user: author).call! }

  # A publication frozen at creation, as the publisher does: its snapshot is
  # read-only afterwards. `title: nil` publishes no title.
  def publication_of(user, *traits, title: "Col du Galibier", notes: "Private note", settings: {})
    workout = create(:workout, user:, title: title || "Untitled", notes:)
    actor = Federation::ActorProvisioner.new(user:).call!
    profile = if traits.include?(:with_followers)
      PublishingProfile.ensure_built_ins_for!(user)
      user.publishing_profiles.find_by!(built_in_key: "followers")
    else
      create(:publishing_profile, :custom, user:)
    end
    profile.update_columns(settings: profile.settings.merge(settings.stringify_keys))
    representation = {
      "sport_slug" => workout.sport.slug,
      "started_at" => workout.started_at.iso8601(6),
      "metrics" => { "distance" => 250.0 },
      "track" => { "type" => "FeatureCollection", "features" => [
        { "type" => "Feature", "geometry" => { "type" => "LineString", "coordinates" => [ [ 6.4, 45.0 ], [ 6.5, 45.1 ] ] },
          "properties" => { "segment_index" => 0 } }
      ] }
    }
    representation["title"] = title if title
    create(:workout_publication, *(traits - [ :with_followers ]), workout:, actor:, publishing_profile: profile, representation:)
  end

  def follow(follower, followed)
    create(:following, :accepted, follower_actor: follower, followed_actor: followed)
  end

  def get_json(path, params: {}) = get("/api/rest/v1#{path}", params:, headers:)

  describe "GET /feed" do
    it "shows the account's own and followed publications, built from the snapshot" do
      follow(reader_actor, author_actor)
      own = publication_of(reader)
      followed = publication_of(author)

      get_json "/feed"

      expect(response).to have_http_status(:ok)
      expect_api_contract
      items = response.parsed_body["data"]
      expect(items.pluck("type")).to all(eq("publication"))
      expect(items.map { it.dig("publication", "id") }).to contain_exactly(own.to_param, followed.to_param)
      expect(items.find { it.dig("publication", "id") == own.to_param }.dig("publication", "own")).to be(true)
      expect(response.body).not_to include("Private note")
    end

    it "adds unfollowed public publications only with public=true, by default only when following nobody" do
      follow(reader_actor, author_actor)
      stranger = publication_of(create(:user))

      get_json "/feed"
      expect(response.parsed_body["data"].map { it.dig("publication", "id") }).not_to include(stranger.to_param)

      get_json "/feed", params: { public: true }
      expect(response.parsed_body["data"].map { it.dig("publication", "id") }).to include(stranger.to_param)
    end

    it "shows a followed author's followers publication while restricted federation is off" do
      allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(false)
      follow(reader_actor, author_actor)
      shown = publication_of(author, :with_followers)

      get_json "/feed"

      expect(response.parsed_body["data"].map { it.dig("publication", "id") }).to include(shown.to_param)
    end

    it "includes the received notes the account is entitled to, never another account's" do
      mine = create(:remote_note)
      create(:remote_note_recipient, remote_note: mine, recipient_actor: reader_actor)
      theirs = create(:remote_note, audience: "followers")
      create(:remote_note_recipient, remote_note: theirs, recipient_actor: author_actor)

      get_json "/feed"

      notes = response.parsed_body["data"].select { it["type"] == "remote_note" }
      expect(notes.map { it.dig("remote_note", "id") }).to eq([ Allure::ShortId.encode(mine.uuid) ])
      expect_api_contract
    end

    it "pages with a cursor" do
      3.times { publication_of(reader) }

      get_json "/feed", params: { limit: 2 }
      first = response.parsed_body
      get_json "/feed", params: { limit: 2, cursor: first["next_cursor"] }

      expect(first["data"].size).to eq(2)
      expect(response.parsed_body["data"].size).to eq(1)
      expect(response.parsed_body["next_cursor"]).to be_nil
    end
  end

  describe "GET /publications/:id" do
    it "reads another member's public publication, the shared fields only" do
      publication = publication_of(author, title: nil)

      get_json "/publications/#{publication.to_param}"

      expect(response).to have_http_status(:ok)
      expect_api_contract
      body = response.parsed_body
      expect(body).to include("own" => false, "audience" => "public")
      expect(body["author"]).to include("handle" => author.handle, "local" => true)
      expect(body).not_to have_key("title")
      expect(body["links"]).to have_key("track")
      expect(response.body).not_to include("Private note", author.email_address)
    end

    it "serves a followers publication to an accepted follower only, whatever restricted federation says" do
      publication = publication_of(author, :with_followers)
      allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(false)

      get_json "/publications/#{publication.to_param}"
      expect(response).to have_http_status(:not_found)

      follow(reader_actor, author_actor)
      get_json "/publications/#{publication.to_param}"
      expect(response).to have_http_status(:ok)
    end

    it "answers 404 for a withdrawn or scheduled publication" do
      withdrawn = publication_of(author)
      withdrawn.mark_deleted!
      scheduled = publication_of(author, :scheduled)

      [ withdrawn, scheduled ].each do |publication|
        get_json "/publications/#{publication.to_param}"
        expect(response).to have_http_status(:not_found)
      end
    end

    it "serves the sanitized track only when the route is shared" do
      publication = publication_of(author)

      get_json "/publications/#{publication.to_param}/track"
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/geo+json")
      expect(JSON.parse(response.body)["type"]).to eq("FeatureCollection")

      hidden = publication_of(author, settings: { route: false })
      get_json "/publications/#{hidden.to_param}/track"
      expect(response).to have_http_status(:not_found)
      get_json "/publications/#{hidden.to_param}"
      expect(response.parsed_body["links"]).not_to have_key("track")
    end

    it "answers 404 for a route image that was not published" do
      publication = publication_of(author)

      get_json "/publications/#{publication.to_param}/route_image"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "comments" do
    it "reads the publication's thread: active comments, a stub kept for its replies, the reader's own removed one" do
      publication = publication_of(author)
      workout = publication.workout
      root = create(:comment, :deleted, workout:, actor: author_actor)
      create(:comment, workout:, parent: root, in_reply_to_uri: root.uri, body: "Reply")
      create(:comment, :removed, workout:, actor: reader_actor, body: "Mine, removed")
      create(:comment, :removed, workout:, body: "Someone else's, removed")

      get_json "/publications/#{publication.to_param}/comments"

      expect(response).to have_http_status(:ok)
      expect_api_contract
      entries = response.parsed_body["data"]
      stub = entries.find { it["id"] == root.to_param }
      expect(stub).to include("state" => "deleted", "body" => nil, "author" => nil)
      expect(stub["replies"].pluck("body")).to eq([ "Reply" ])
      expect(entries.pluck("body")).to include("Mine, removed")
      expect(response.body).not_to include("Someone else's, removed")
    end

    it "keeps the followers thread out of a public publication's comments" do
      publication = publication_of(author)
      create(:comment, workout: publication.workout, audience: "followers", body: "For followers")

      get_json "/publications/#{publication.to_param}/comments"

      expect(response.body).not_to include("For followers")
    end

    it "gives the owner every thread of their workout, and nobody else" do
      publication = publication_of(reader)
      create(:comment, workout: publication.workout, audience: "followers", body: "For followers")

      get_json "/workouts/#{publication.workout.to_param}/comments"
      expect(response.parsed_body["data"].pluck("body")).to include("For followers")
      expect_api_contract

      get_json "/workouts/#{publication_of(author).workout.to_param}/comments"
      expect(response).to have_http_status(:not_found)
    end
  end

  it "counts the owner's reactions, naming nobody" do
    publication = publication_of(reader)
    create(:reaction, workout: publication.workout, kind: "beer")

    get_json "/workouts/#{publication.workout.to_param}/reactions"

    expect(response.parsed_body).to eq("counts" => { "beer" => 1, "energy" => 0, "coffee" => 0, "like" => 0 }, "mine" => nil)
    expect_api_contract
  end

  describe "GET /remote_notes/:id" do
    it "reads a public received note as plain text" do
      note = create(:remote_note, content_html: "<p>Remote <b>hike</b></p>")

      get_json "/remote_notes/#{Allure::ShortId.encode(note.uuid)}"

      expect(response).to have_http_status(:ok)
      expect_api_contract
      expect(response.parsed_body).to include("title" => "Remote hike", "sport_label" => "Hiking", "media" => "none")
      expect(response.body).not_to include("<b>")
    end

    it "serves a followers note only with an active entitlement" do
      note = create(:remote_note, audience: "followers")
      path = "/remote_notes/#{Allure::ShortId.encode(note.uuid)}"

      get_json path
      expect(response).to have_http_status(:not_found)

      entitlement = create(:remote_note_recipient, remote_note: note, recipient_actor: reader_actor)
      get_json path
      expect(response).to have_http_status(:ok)

      entitlement.update_columns(status: "withdrawn", withdrawn_at: Time.current, withdrawal_reason: "deleted")
      get_json path
      expect(response).to have_http_status(:not_found)
    end

    it "answers 404 for a deleted note and an unknown identifier" do
      get_json "/remote_notes/#{Allure::ShortId.encode(create(:remote_note, :deleted).uuid)}"
      expect(response).to have_http_status(:not_found)

      get_json "/remote_notes/nope"
      expect(response).to have_http_status(:not_found)
    end
  end

  it "lists accepted followers and followings, never pending ones" do
    follower = Federation::ActorProvisioner.new(user: create(:user, display_name: "Fan")).call!
    follow(follower, reader_actor)
    create(:following, follower_actor: Federation::ActorProvisioner.new(user: create(:user)).call!, followed_actor: reader_actor)
    follow(reader_actor, author_actor)

    get_json "/followers"
    expect(response.parsed_body["data"].pluck("display_name")).to eq([ "Fan" ])
    expect_api_contract

    get_json "/following"
    expect(response.parsed_body["data"].pluck("handle")).to eq([ author.handle ])
  end

  it "needs the social:read scope" do
    get "/api/rest/v1/feed", headers: api_headers_for(reader, scopes: %w[read])

    expect(response.parsed_body["code"]).to eq("insufficient_scope")
  end
end
