# frozen_string_literal: true

require "rails_helper"

RSpec.describe Reactions::Toggle do
  let(:owner) { create(:user) }
  let(:viewer) { create(:user) }
  let(:workout) { create(:workout, user: owner) }

  def toggle(user: viewer, target: workout, kind: "beer")
    described_class.new(user:, target:, kind:)
  end

  describe "a local publication" do
    before { create(:workout_publication, workout:) }

    it "creates a local reaction with no protocol identity and notifies the owner" do
      expect {
        toggle.call!
      }.to change(Reaction, :count).by(1)
        .and change { Notification.where(user: owner, kind: "reaction").count }.by(1)
      expect(FederationOutboxEvent.count).to eq(0)

      reaction = Reaction.last
      expect(reaction.kind).to eq("beer")
      expect(reaction.workout).to eq(workout)
      expect(reaction.uri).to start_with("#{Allure::Federation.config.base_url}/local_reactions/")
      expect(Notification.last.actor).to eq(viewer.reload.actor)
    end

    it "withdraws the reaction and its notification when the same type is repeated" do
      toggle.call!
      reaction = Reaction.last

      expect {
        toggle.call!
      }.not_to change(Reaction, :count)

      expect(reaction.reload).not_to be_active
      expect(Notification.where(user: owner, kind: "reaction")).to be_empty
    end

    it "switches to another type as a new reaction with its own identity" do
      toggle.call!
      old = Reaction.last
      Notification.find_by!(user: owner, kind: "reaction").update!(read_at: 1.hour.ago)

      expect {
        described_class.new(user: viewer, target: workout, kind: "coffee").call!
      }.to change(Reaction, :count).by(1)

      expect(old.reload).not_to be_active
      active = Reaction.active.find_by!(actor: viewer.actor, workout:)
      expect(active.kind).to eq("coffee")
      expect(active.uri).not_to eq(old.uri)
      notice = Notification.find_by!(user: owner, kind: "reaction")
      expect(notice.subject).to eq(workout)
      expect(notice.payload).to eq("count" => 1, "kinds" => { "coffee" => 1 })
      expect(notice).to be_read
    end

    it "refuses a self-reaction from the owner" do
      expect {
        described_class.new(user: owner, target: workout, kind: "beer").call!
      }.to raise_error(described_class::NotAllowed)
    end

    it "refuses a reaction to an unpublished workout" do
      expect {
        described_class.new(user: viewer, target: create(:workout), kind: "beer").call!
      }.to raise_error(described_class::NotAllowed)
    end

    it "refuses an unknown type before touching the target" do
      expect {
        described_class.new(user: viewer, target: workout, kind: "wine").call!
      }.to raise_error(described_class::InvalidKind)
    end

    it "serves an accepted follower on a followers-only publication" do
      allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(true)
      followers_workout = create(:workout, user: owner)
      follower_actor = Federation::ActorProvisioner.new(user: viewer).call!
      followed_actor = Federation::ActorProvisioner.new(user: owner).call!
      create(:following, :accepted, follower_actor:, followed_actor:)
      create(:workout_publication, :with_followers, workout: followers_workout)

      expect {
        described_class.new(user: viewer, target: followers_workout, kind: "beer").call!
      }.to change(Reaction, :count).by(1)
      expect(Reaction.last.audience).to eq("followers")
    end

    it "records a public reaction while a public version is live" do
      expect(toggle.call!.audience).to eq("public")
    end

    # PLAN_REACTIONS.md §2: a follower served the followers version reveals
    # nothing by reacting while the public version is live too.
    it "records a follower's reaction as public while both versions are live" do
      allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(true)
      create(:following, :accepted, follower_actor: Federation::ActorProvisioner.new(user: viewer).call!,
                                    followed_actor: Federation::ActorProvisioner.new(user: owner).call!)
      create(:workout_publication, :with_followers, workout:)

      expect(toggle.call!.audience).to eq("public")
    end
  end

  describe "a received note" do
    let(:note) { create(:remote_note, actor: create(:actor, uri: "https://remote.example/users/demo")) }

    before do
      viewer_actor = Federation::ActorProvisioner.new(user: viewer).call!
      create(:remote_note_recipient, remote_note: note, recipient_actor: viewer_actor)
    end

    it "mints the Like activity URI and queues the outbound Like" do
      expect {
        toggle(target: note, kind: "energy").call!
      }.to change(Reaction, :count).by(1)
        .and change(FederationOutboxEvent, :count).by(1)
        .and have_enqueued_job(Federation::ExpandOutboxEventJob)

      reaction = Reaction.last
      event = FederationOutboxEvent.last
      expect(reaction.remote_target?).to be(true)
      expect(reaction.audience).to eq(note.audience)
      expect(reaction.uri).to eq(event.activity_uri)
      expect(event.activity_type).to eq("Like")
      expect(event.payload["object"]).to eq(note.object_uri)
      expect(event.payload["_allure_reaction"]).to eq("energy")
      expect(event.audience["to"]).to eq([ note.actor.uri ])
    end

    it "queues an Undo carrying the Like identity when withdrawn" do
      toggle(target: note, kind: "beer").call!
      reaction = Reaction.last
      toggle(target: note, kind: "beer").call!

      undo = FederationOutboxEvent.find_by!(activity_type: "Undo")
      expect(undo.payload["object"]).to eq({ "type" => "Like", "id" => reaction.uri })
      expect(reaction.reload).not_to be_active
    end

    it "queues an Undo and a new Like when the type changes" do
      toggle(target: note, kind: "beer").call!
      old = Reaction.last
      toggle(target: note, kind: "coffee").call!

      expect(FederationOutboxEvent.where(activity_type: "Undo").count).to eq(1)
      expect(FederationOutboxEvent.where(activity_type: "Like").count).to eq(2)
      expect(Reaction.active.find_by!(actor: viewer.actor, remote_note: note).kind).to eq("coffee")
      expect(old.reload).not_to be_active
    end

    it "refuses a followers note the viewer is not entitled to" do
      private_note = create(:remote_note, audience: "followers", actor: note.actor)

      expect {
        described_class.new(user: viewer, target: private_note, kind: "beer").call!
      }.to raise_error(described_class::NotAllowed)
    end

    it "does not notify anyone locally" do
      expect {
        toggle(target: note, kind: "beer").call!
      }.not_to change(Notification, :count)
    end
  end
end
