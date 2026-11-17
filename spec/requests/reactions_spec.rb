# frozen_string_literal: true

require "rails_helper"

# The reaction gesture (docs/dev/REACTIONS.md, DESIGN.md §10.17): one PUT
# toggles the viewer's reaction inside a Turbo Frame, the bar renders in the
# feed and on the detail pages, and the owner or a visitor only ever reads
# counts.
RSpec.describe "Reactions" do
  let(:owner) { create(:user, username: "marie") }
  let(:viewer) { create(:user, username: "paul") }
  let(:workout) { create(:workout, user: owner, title: "Sortie du soir") }

  def publish!(workout, audience: "public")
    PublishingProfile.ensure_built_ins_for!(workout.user)
    profile = workout.user.publishing_profiles.find_by!(built_in_key: audience == "public" ? "public" : "followers")
    create(:workout_publication, workout:, publishing_profile: profile)
  end

  def frame_headers(target)
    { "Turbo-Frame" => "reaction-bar-#{target.model_name.name.underscore.dasherize}-#{target.id}" }
  end

  describe "the workout endpoint" do
    let!(:publication) { publish!(workout) }

    it "redirects an anonymous visitor to sign-in" do
      put workout_reaction_path(workout), params: { reaction: { kind: "beer" } }

      expect(response).to redirect_to(new_session_path)
      expect(Reaction.count).to eq(0)
    end

    it "toggles the reaction for a signed-in viewer inside the Turbo Frame" do
      sign_in_as(viewer)

      expect {
        put workout_reaction_path(workout), params: { reaction: { kind: "beer" } },
            headers: frame_headers(workout)
      }.to change(Reaction, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(aria-pressed="true"))
      expect(response.body).to include("allure-reactions__pill--active allure-reactions__pill--mine")
      expect(response.body).to include(%(data-bs-title="Vous avez trinqué à cette activité"))
      expect(response.body).to include("1")
      expect(Reaction.last.kind).to eq("beer")
    end

    it "withdraws the reaction when the same type is sent again" do
      sign_in_as(viewer)
      put workout_reaction_path(workout), params: { reaction: { kind: "beer" } }, headers: frame_headers(workout)
      reaction = Reaction.last

      expect {
        put workout_reaction_path(workout), params: { reaction: { kind: "beer" } }, headers: frame_headers(workout)
      }.not_to change(Reaction, :count)

      expect(response).to have_http_status(:ok)
      expect(reaction.reload).not_to be_active
      expect(response.body).not_to include(%(aria-pressed="true"))
    end

    it "redirects a request without a Turbo Frame back to the workout" do
      sign_in_as(viewer)

      expect {
        put workout_reaction_path(workout), params: { reaction: { kind: "coffee" } }
      }.to change(Reaction, :count).by(1)

      expect(response).to redirect_to(workout_path(workout))
    end

    it "refuses the owner" do
      sign_in_as(owner)

      expect {
        put workout_reaction_path(workout), params: { reaction: { kind: "beer" } }
      }.not_to change(Reaction, :count)

      expect(response).to have_http_status(:not_found)
    end

    it "refuses an unpublished workout" do
      unpublished = create(:workout, user: owner)
      sign_in_as(viewer)

      put workout_reaction_path(unpublished), params: { reaction: { kind: "beer" } }

      expect(response).to have_http_status(:not_found)
    end

    it "rejects an unknown type" do
      sign_in_as(viewer)

      put workout_reaction_path(workout), params: { reaction: { kind: "wine" } },
          headers: frame_headers(workout)

      expect(response).to have_http_status(:unprocessable_content)
      expect(Reaction.count).to eq(0)
    end
  end

  describe "the received-note endpoint" do
    let(:remote_author) { create(:actor, uri: "https://remote.example/users/demo") }
    let(:note) { create(:remote_note, actor: remote_author) }

    it "toggles for an entitled viewer and queues the outbound Like" do
      viewer_actor = Federation::ActorProvisioner.new(user: viewer).call!
      create(:remote_note_recipient, remote_note: note, recipient_actor: viewer_actor)
      sign_in_as(viewer)

      expect {
        put remote_note_reaction_path(note), params: { reaction: { kind: "energy" } },
            headers: frame_headers(note)
      }.to change(Reaction, :count).by(1)
        .and change(FederationOutboxEvent, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(FederationOutboxEvent.last.payload["_allure_reaction"]).to eq("energy")
    end

    it "refuses a followers note without an entitlement" do
      note.update!(audience: "followers")
      sign_in_as(viewer)

      expect {
        put remote_note_reaction_path(note), params: { reaction: { kind: "beer" } }
      }.not_to change(Reaction, :count)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "the bar in the feed" do
    let!(:publication) { publish!(workout) }

    it "shows read-only counts to the owner" do
      create(:reaction, :beer, workout:, actor: create(:actor, display_name: "Éric"))
      sign_in_as(owner)

      get feed_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("allure-reactions__pill--readonly")
      expect(response.body).to include("allure-reactions__pill--active")
      expect(response.body).to include("Bière, une réaction")
      expect(response.body).to include(%(data-bs-title="Éric a trinqué à votre activité"))
      expect(response.body).not_to include(%(name="reaction[kind]"))
    end

    it "shows no bar at all to the owner while nothing was said" do
      sign_in_as(owner)

      get feed_path

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("allure-reactions")
    end

    it "shows buttons to a signed-in viewer and none to the owner" do
      Federation::ActorProvisioner.new(user: viewer).call!
      create(:following, :accepted,
             follower_actor: viewer.actor,
             followed_actor: Federation::ActorProvisioner.new(user: owner).call!)
      sign_in_as(viewer)

      get feed_path

      expect(response.body).to include(%(name="reaction[kind]" value="beer"))
      expect(response.body).to include(%(aria-pressed="false"))
      expect(response.body).to include("allure-reactions__pill--empty")
      expect(response.body).not_to include("allure-reactions__pill--active")
      expect(response.body).to include(%(data-controller="tooltip"))
      expect(response.body).to include(%(data-bs-title="Réagir : Bière"))

      sign_in_as(owner)
      create(:reaction, :beer, workout:, actor: create(:actor))

      get feed_path

      expect(response.body).to include("allure-reactions__pill--readonly")
      expect(response.body).not_to include(%(name="reaction[kind]"))
    end
  end

  describe "the bar on the workout page" do
    let!(:publication) { publish!(workout) }

    it "offers the buttons to a signed-in non-owner and reads only counts for the owner" do
      create(:reaction, :beer, workout:, actor: create(:actor))
      sign_in_as(viewer)

      get workout_path(workout)
      expect(response.body).to include(%(name="reaction[kind]" value="beer"))
      expect(response.body).to include(%(aria-label="Bière, une réaction"))

      sign_in_as(owner)
      get workout_path(workout)

      expect(response.body).to include("allure-reactions__pill--readonly")
      expect(response.body).not_to include(%(name="reaction[kind]"))
    end
  end

  describe "the reactor tooltip" do
    let!(:publication) { publish!(workout) }

    it "names every reactor to the owner, up to three then the rest" do
      {
        "Éric" => 1.hour.ago, "Marc" => 2.hours.ago, "Sophie" => 3.hours.ago,
        "Joan" => 4.hours.ago, "Inès" => 5.hours.ago
      }.each do |name, at|
        create(:reaction, :beer, workout:, actor: create(:actor, display_name: name),
                                    created_at: at, updated_at: at)
      end
      sign_in_as(owner)

      get workout_path(workout)

      expect(response.body).to include(
        %(data-bs-title="Éric, Marc, Sophie et 2 autres personnes ont trinqué à votre activité")
      )
    end

    it "names the reactors to another reader on this activity" do
      create(:reaction, :beer, workout:, actor: create(:actor, display_name: "Éric"))
      sign_in_as(viewer)

      get workout_path(workout)

      expect(response.body).to include(%(data-bs-title="Éric a trinqué à cette activité"))
    end

    # docs/dev/REACTIONS.md: a reaction given through the followers version
    # counts for every reader but is named only to that audience.
    it "counts a followers reaction for a public reader without naming it" do
      allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(true)
      create(:reaction, :beer, :followers, workout:, actor: create(:actor, display_name: "Éric"))
      sign_in_as(viewer)

      get workout_path(workout)

      expect(response.body).to include(%(data-bs-title="Une personne a trinqué à cette activité"))
      expect(response.body).not_to include("Éric")

      sign_in_as(owner)
      get workout_path(workout)

      expect(response.body).to include(%(data-bs-title="Éric a trinqué à votre activité"))
    end

    it "joins two names for the owner" do
      create(:reaction, :beer, workout:, actor: create(:actor, display_name: "Éric"),
                                  created_at: 1.hour.ago, updated_at: 1.hour.ago)
      create(:reaction, :beer, workout:, actor: create(:actor, display_name: "Marc"),
                                  created_at: 2.hours.ago, updated_at: 2.hours.ago)
      sign_in_as(owner)

      get workout_path(workout)

      expect(response.body).to include(%(data-bs-title="Éric et Marc ont trinqué à votre activité"))
    end

    it "leads with « Vous » when the viewer reacted too" do
      viewer_actor = Federation::ActorProvisioner.new(user: viewer).call!
      create(:reaction, :beer, workout:, actor: viewer_actor)
      create(:reaction, :beer, workout:, actor: create(:actor, display_name: "Marc"),
                                  created_at: 2.hours.ago, updated_at: 2.hours.ago)
      sign_in_as(viewer)

      get workout_path(workout)

      expect(response.body).to include(%(data-bs-title="Vous et Marc avez trinqué à cette activité"))
    end

    it "names the reactors of a received note" do
      viewer_actor = Federation::ActorProvisioner.new(user: viewer).call!
      note = create(:remote_note, actor: create(:actor, acct: "demo@remote.example",
                                                          handle: "demo@remote.example"))
      create(:remote_note_recipient, remote_note: note, recipient_actor: viewer_actor)
      create(:reaction, :remote_note, remote_note: note, kind: "coffee",
                                      actor: create(:actor, display_name: "Éric"))
      sign_in_as(viewer)

      get remote_note_path(note)

      expect(response.body).to include(%(data-bs-title="Éric a offert un café à cette activité"))
    end
  end

  describe "the bar on a received note page" do
    it "offers the buttons to an entitled viewer" do
      viewer_actor = Federation::ActorProvisioner.new(user: viewer).call!
      remote_author = create(:actor, uri: "https://remote.example/users/demo",
                                     acct: "demo@remote.example", handle: "demo@remote.example")
      note = create(:remote_note, actor: remote_author)
      create(:remote_note_recipient, remote_note: note, recipient_actor: viewer_actor)
      sign_in_as(viewer)

      get remote_note_path(note)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(name="reaction[kind]" value="beer"))
      expect(response.body).to include(%(aria-label="Bière, aucune réaction"))
    end
  end
end
