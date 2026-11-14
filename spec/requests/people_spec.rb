# frozen_string_literal: true

require "rails_helper"

RSpec.describe "People" do
  let(:user) { create(:user) }
  let(:local) { Federation::ActorProvisioner.new(user:).call! }
  let(:remote) do
    create(
      :actor,
      uri: "https://remote.example/users/demo",
      handle: "demo@remote.example",
      display_name: "Demo Remote"
    )
  end
  let(:actor_resolver) { instance_double(Federation::ActorResolver) }
  let(:webfinger_resolver) { instance_double(Federation::WebFingerResolver) }

  before do
    allow(Federation::ActorResolver).to receive(:new).and_return(actor_resolver)
    allow(Federation::WebFingerResolver).to receive(:new).and_return(webfinger_resolver)
  end

  it "requires authentication" do
    get people_path

    expect(response).to redirect_to(new_session_path)
  end

  it "renders the hub views as Tabler navigation tabs, not an ARIA tab widget" do
    sign_in_as(user)

    get people_path

    tabs = response.parsed_body.at_css(".card-header .nav-tabs")
    expect(tabs["class"]).to eq("nav nav-tabs card-header-tabs")
    expect(tabs["aria-label"]).to eq(I18n.t("people.tabs.label"))
    expect(tabs["role"]).to be_nil
    active = tabs.at_css(".nav-link.active")
    expect(active["aria-current"]).to eq("page")
    expect(active["aria-selected"]).to be_nil
  end

  it "lists accepted relationships and pending requests" do
    sign_in_as(user)
    follower = create(:actor, uri: "https://remote.example/users/follower", handle: "follower@remote.example")
    create(:following, :accepted, follower_actor: local, followed_actor: remote,
                                 uri: "https://remote.example/activities/follow-out-#{SecureRandom.hex(4)}")
    create(:following, follower_actor: follower, followed_actor: local,
                       uri: "https://remote.example/activities/follow-in-#{SecureRandom.hex(4)}")

    get people_path
    expect(response.body).to include("Demo Remote")

    get people_path(tab: "requests")
    expect(response.body).to include("follower@remote.example")
    expect(response.body).to include(ERB::Util.html_escape(I18n.t("people.incoming.title")))
  end

  it "renders a local follower's account avatar on the people page" do
    sign_in_as(user)
    follower = create(:user, username: "paul")
    follower.avatar.attach(io: StringIO.new("uploaded"), filename: "avatar.webp", content_type: "image/webp")
    follower_actor = Federation::ActorProvisioner.new(user: follower).call!
    create(:following, :accepted, follower_actor:, followed_actor: local,
                                 uri: "https://remote.example/activities/follow-local-in-#{SecureRandom.hex(4)}")

    get people_path(tab: "followers")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(%(src="#{profile_avatar_path("paul")}"))
    expect(response.body).not_to include("/rails/active_storage")
  end

  it "resolves a cached remote actor and redirects to its profile" do
    sign_in_as(user)
    target = "https://remote.example/users/demo"
    actor = build(:actor, uri: target, handle: "demo@remote.example", acct: "demo@remote.example")
    allow(actor_resolver).to receive(:resolve).with(target).and_return(actor)

    post resolve_people_path, params: { target: }

    expect(response).to redirect_to(remote_profile_path("demo@remote.example"))
  end

  it "redirects back with an alert when the target cannot be resolved" do
    sign_in_as(user)
    allow(actor_resolver).to receive(:resolve).and_raise(Federation::ActorResolver::FetchError, "unreachable")

    post resolve_people_path, params: { target: "https://remote.example/users/unknown" }

    expect(response).to redirect_to(people_path)
    expect(flash[:alert]).to be_present
  end

  it "keeps a local follow pending until the target accepts it" do
    marie = create(:user, username: "marie")
    paul = create(:user, username: "paul")
    sign_in_as(marie)

    post federation_follow_path, params: { target: "paul" }

    marie_actor = Federation::ActorProvisioner.new(user: marie).call!
    paul_actor = Federation::ActorProvisioner.new(user: paul).call!
    following = Following.find_by!(follower_actor: marie_actor, followed_actor: paul_actor)
    expect(following).to be_pending
    expect(FederationOutboxEvent.count).to eq(0)

    sign_in_as(paul)
    get people_path(tab: "requests")
    expect(response.body).to include(ERB::Util.html_escape(I18n.t("people.incoming.title")), "marie")

    patch people_follow_path(following), params: { decision: "accept" }

    expect(following.reload).to be_accepted
    expect(FederationOutboxEvent.count).to eq(0)

    sign_in_as(marie)
    get people_path
    expect(response.body).to include("paul")
  end

  it "accepts an inbound follow request owned by the current user" do
    sign_in_as(user)
    following = create(
      :following, follower_actor: remote, followed_actor: local,
      uri: "https://remote.example/activities/follow-3"
    )

    patch people_follow_path(following), params: { decision: "accept" }

    expect(response).to redirect_to(people_path)
    expect(following.reload).to be_accepted
  end

  it "cannot decide another account's follow request" do
    other_actor = Federation::ActorProvisioner.new(user: create(:user)).call!
    following = create(
      :following, follower_actor: remote, followed_actor: other_actor,
      uri: "https://remote.example/activities/follow-4"
    )
    sign_in_as(user)

    patch people_follow_path(following), params: { decision: "accept" }

    expect(response).to have_http_status(:not_found)
    expect(following.reload).to be_pending
  end

  describe "name search" do
    it "explains that a hidden account is not searchable" do
      sign_in_as(user)

      get people_path

      expect(response.body).to include(ERB::Util.html_escape(I18n.t("people.discoverability.hidden")))
    end

    it "hides that note once the account is discoverable" do
      user.update!(discoverable: "members")
      sign_in_as(user)

      get people_path

      expect(response.body).not_to include(ERB::Util.html_escape(I18n.t("people.discoverability.hidden")))
    end

    it "returns a minimal result for a discoverable account" do
      sign_in_as(user)
      create(:user, username: "marie", display_name: "Marie Dufour", bio: "Secret bio", discoverable: "members")

      get search_people_path(q: "mar")

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Marie Dufour", "@marie")
      expect(response.body).not_to include("Secret bio")
    end

    it "never returns a hidden account" do
      sign_in_as(user)
      create(:user, username: "hidden", display_name: "Hidden Person")

      get search_people_path(q: "hid")

      expect(response.body).to include(ERB::Util.html_escape(I18n.t("people.search.no_results")))
      expect(response.body).not_to include("Hidden Person")
    end

    it "requires at least three characters" do
      sign_in_as(user)
      create(:user, username: "marie", discoverable: "members")

      get search_people_path(q: "ma")

      expect(response.body).not_to include("@marie")
    end

    it "is never cached" do
      sign_in_as(user)

      get search_people_path(q: "mar")

      expect(response.headers["Cache-Control"]).to include("no-store")
    end
  end

  describe "removing a follower" do
    it "undoes a local follow" do
      sign_in_as(user)
      follower = create(:user, username: "paul")
      following = create(:following, :accepted, follower_actor: Federation::ActorProvisioner.new(user: follower).call!,
                                                followed_actor: local,
                                                uri: "https://remote.example/activities/follow-local-in")

      delete people_follower_path(following)

      expect(response).to redirect_to(people_path(tab: "followers"))
      expect(following.reload).to be_undone
    end

    it "sends a signed Reject to a remote follower" do
      sign_in_as(user)
      following = create(:following, :accepted, follower_actor: remote, followed_actor: local,
                                                uri: "https://remote.example/activities/follow-in")

      delete people_follower_path(following)

      expect(following.reload).to be_undone
      event = FederationOutboxEvent.find_by!(activity_type: "Reject")
      expect(event.payload.fetch("object")).to eq(following.uri)
      expect(event.audience.fetch("to")).to eq([ remote.uri ])
    end

    it "cannot remove another account's follower" do
      other_actor = Federation::ActorProvisioner.new(user: create(:user)).call!
      following = create(:following, :accepted, follower_actor: remote, followed_actor: other_actor,
                                                uri: "https://remote.example/activities/follow-other")
      sign_in_as(user)

      delete people_follower_path(following)

      expect(response).to have_http_status(:not_found)
      expect(following.reload).to be_accepted
    end
  end

  describe "suggestions" do
    it "dismisses one permanently" do
      sign_in_as(user)
      actor = Federation::ActorProvisioner.new(user: create(:user, username: "marie", discoverable: "members")).call!

      delete people_suggestion_path(actor)

      expect(response).to redirect_to(people_path)
      expect(PeopleSuggestionDismissal.where(user:, actor:)).to exist
    end
  end

  # Relationships between accounts of this instance never depend on the
  # federation switch; only remote accounts are out of reach.
  context "with federation disabled" do
    around do |example|
      previous = ENV["FEDERATION_ENABLED"]
      ENV["FEDERATION_ENABLED"] = "false"
      example.run
    ensure
      previous.nil? ? ENV.delete("FEDERATION_ENABLED") : ENV["FEDERATION_ENABLED"] = previous
    end

    it "lists local relationships only, with the local search copy" do
      sign_in_as(user)
      paul_actor = Federation::ActorProvisioner.new(user: create(:user, username: "paul", display_name: "Paul Local")).call!
      create(:following, :accepted, follower_actor: local, followed_actor: paul_actor,
                                   uri: "https://remote.example/activities/follow-local-#{SecureRandom.hex(4)}")
      create(:following, :accepted, follower_actor: local, followed_actor: remote,
                                   uri: "https://remote.example/activities/follow-out-#{SecureRandom.hex(4)}")
      create(:following, follower_actor: create(:actor, uri: "https://remote.example/users/follower", handle: "follower@remote.example"),
                         followed_actor: local, uri: "https://remote.example/activities/follow-in-#{SecureRandom.hex(4)}")

      get people_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Paul Local", ERB::Util.html_escape(I18n.t("people.search.local_hint")))
      expect(response.body).not_to include("Demo Remote", "follower@remote.example")
      expect(response.body).not_to include(ERB::Util.html_escape(I18n.t("people.incoming.title")))
    end

    it "follows, accepts and unfollows a local account without any federation event" do
      marie = create(:user, username: "marie")
      paul = create(:user, username: "paul")
      sign_in_as(marie)

      post federation_follow_path, params: { target: "paul" }
      following = Following.sole
      expect(following).to be_pending

      sign_in_as(paul)
      patch people_follow_path(following), params: { decision: "accept" }
      expect(following.reload).to be_accepted

      sign_in_as(marie)
      get profile_path("paul")
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("follows.actions.unfollow")))

      delete federation_follow_path, params: { target: "paul" }
      expect(following.reload).not_to be_accepted
      expect(Following.active).to be_empty
      expect(FederationOutboxEvent.count).to eq(0)
    end

    it "shows the follow button on a local profile" do
      create(:user, username: "paul")
      sign_in_as(user)

      get profile_path("paul")

      expect(response.body).to include(ERB::Util.html_escape(I18n.t("follows.actions.follow")))
    end

    it "resolves a local account" do
      create(:user, username: "paul")
      sign_in_as(user)

      post resolve_people_path, params: { target: "paul" }

      expect(response).to redirect_to(profile_path("paul"))
    end

    %w[@demo@remote.example https://remote.example/users/demo].each do |target|
      it "refuses to resolve #{target} before any request" do
        allow(actor_resolver).to receive(:resolve)
        allow(webfinger_resolver).to receive(:resolve)
        sign_in_as(user)

        post resolve_people_path, params: { target: }

        expect(response).to redirect_to(people_path)
        expect(flash[:alert]).to eq(I18n.t("people.search.invalid"))
        expect(actor_resolver).not_to have_received(:resolve)
        expect(webfinger_resolver).not_to have_received(:resolve)
      end
    end

    it "refuses to follow a remote account" do
      allow(webfinger_resolver).to receive(:resolve)
      sign_in_as(user)

      post federation_follow_path, params: { target: "@demo@remote.example" }

      expect(flash[:alert]).to eq(I18n.t("federation_follow.errors.invalid_target"))
      expect(webfinger_resolver).not_to have_received(:resolve)
      expect(Following.count).to eq(0)
    end

    it "does not decide a remote follower's request" do
      sign_in_as(user)
      following = create(:following, follower_actor: remote, followed_actor: local,
                                     uri: "https://remote.example/activities/follow-5")

      patch people_follow_path(following), params: { decision: "accept" }

      expect(response).to have_http_status(:not_found)
      expect(following.reload).to be_pending
      expect(FederationOutboxEvent.count).to eq(0)
    end
  end
end
