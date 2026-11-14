# frozen_string_literal: true

require "rails_helper"

RSpec.describe Comments::Post do
  let(:owner) { create(:user) }
  let(:viewer) { create(:user) }
  let(:workout) { create(:workout, user: owner) }

  def publish!(target = workout, profile: nil)
    profile ||= public_publishing_profile_for(target.user)
    create(:workout_publication, workout: target, publishing_profile: profile)
  end

  def post(user: viewer, target: workout, body: "Belle sortie !", parent: nil)
    described_class.new(user:, target:, body:, parent_id: parent&.to_param).call!
  end

  describe "on a public publication" do
    let!(:publication) { publish! }

    it "stores a member's comment under the active publication and tells the owner" do
      comment = nil
      expect { comment = post }.to change(Comment, :count).by(1)
        .and change { Notification.where(user: owner, kind: "comment").count }.by(1)

      expect(comment.workout).to eq(workout)
      expect(comment.actor).to eq(viewer.reload.actor)
      expect(comment.in_reply_to_uri).to eq(publication.object_uri)
      expect(comment.audience).to eq("public")
      expect(comment.body).to eq("Belle sortie !")
      expect(Notification.last.actor).to eq(viewer.actor)
      expect(FederationOutboxEvent.pluck(:activity_type)).to eq([ "Announce" ])
    end

    it "lets the owner take part without notifying themselves" do
      expect { post(user: owner) }.to change(Comment, :count).by(1)

      expect(Notification.where(kind: "comment")).to be_empty
    end

    it "answers a top-level comment and tells its author and the owner once each" do
      root = post(user: create(:user))
      Notification.delete_all

      reply = post(parent: root, body: "Merci !")

      expect(reply.parent).to eq(root)
      expect(reply.in_reply_to_uri).to eq(root.uri)
      expect(Notification.where(kind: "comment", subject: reply).pluck(:user_id))
        .to contain_exactly(owner.id, root.actor.user_id)
    end

    it "notifies the owner once when the reply answers the owner's own comment" do
      root = post(user: owner)

      expect { post(parent: root) }.to change { Notification.where(user: owner, kind: "comment").count }.by(1)
    end

    it "keeps replies one level deep and inside their thread" do
      root = post
      reply = post(parent: root)
      other_workout = create(:workout, user: owner)
      publish!(other_workout)
      elsewhere = post(target: other_workout)

      expect { post(parent: reply) }.to raise_error(described_class::Invalid) { |error| expect(error.reason).to eq(:parent) }
      expect { post(parent: elsewhere) }.to raise_error(described_class::Invalid) { |error| expect(error.reason).to eq(:parent) }

      root.mark_deleted!
      expect { post(parent: root) }.to raise_error(described_class::Invalid) { |error| expect(error.reason).to eq(:parent) }
    end

    it "refuses a malformed parent identifier as an invalid reply" do
      expect {
        described_class.new(user: viewer, target: workout, body: "Oui", parent_id: "not-a-short-id").call!
      }.to raise_error(described_class::Invalid)
    end

    it "normalizes the text and refuses an empty or oversized one" do
      comment = post(body: "  \r\nPremier\r\n\r\n\r\n\r\nSecond\u0000\u0007  ")

      expect(comment.body).to eq("Premier\n\nSecond")
      expect { post(body: " \u00A0\n ") }.to raise_error(described_class::Invalid) { |error| expect(error.reason).to eq(:blank) }
      expect { post(body: "a" * (Comment::MAX_BODY_LENGTH + 1)) }
        .to raise_error(described_class::Invalid) { |error| expect(error.reason).to eq(:too_long) }
      expect(post(body: "é" * Comment::MAX_BODY_LENGTH).body.length).to eq(Comment::MAX_BODY_LENGTH)
    end

    it "stops a full thread" do
      stub_const("Comment::MAX_ACTIVE_PER_THREAD", 1)
      post

      expect { post }.to raise_error(described_class::Invalid) { |error| expect(error.reason).to eq(:full) }
    end

    it "follows the publication that is active right now" do
      first = post
      publication.mark_deleted!
      replacement = publish!

      expect(post.in_reply_to_uri).to eq(replacement.object_uri)
      expect(first.reload.in_reply_to_uri).to eq(publication.object_uri)
    end
  end

  describe "refusals" do
    it "refuses an anonymous visitor and an unpublished workout" do
      expect { post(user: nil) }.to raise_error(described_class::NotAllowed)
      expect { post }.to raise_error(described_class::NotAllowed)
    end

    it "refuses a scheduled publication until it is live" do
      create(:workout_publication, :scheduled, workout:, publishing_profile: public_publishing_profile_for(owner))

      expect { post }.to raise_error(described_class::NotAllowed)
    end

    it "says a thread is closed when the owner closed it" do
      publish!
      workout.update!(comments_closed_at: Time.current)

      expect { post }.to raise_error(described_class::Closed)
      expect { post(user: owner) }.to raise_error(described_class::Closed)
    end

    it "says a thread is closed when the profile closed it" do
      create(:workout_publication, workout:, publishing_profile: public_publishing_profile_for(owner),
                                   comments_closed: true)

      expect { post }.to raise_error(described_class::Closed)
      expect { post(user: owner) }.to raise_error(described_class::Closed)
    end

    it "serves a followers publication to accepted local followers only, whatever restricted federation says" do
      allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(false)
      followers_profile = create(:publishing_profile, :followers, user: owner)
      publish!(profile: followers_profile)
      owner_actor = Federation::ActorProvisioner.new(user: owner).call!
      viewer_actor = Federation::ActorProvisioner.new(user: viewer).call!
      create(:following, :accepted, follower_actor: viewer_actor, followed_actor: owner_actor)

      expect(post.audience).to eq("followers")
      expect { post(user: create(:user)) }.to raise_error(described_class::NotAllowed)
    end
  end

  describe ".permission" do
    it "names the three states the card renders" do
      expect(described_class.permission(user: viewer, target: workout)).to eq(:denied)

      publish!
      workout.reload
      expect(described_class.permission(user: viewer, target: workout)).to eq(:allowed)
      expect(described_class.permission(user: nil, target: workout)).to eq(:denied)

      workout.update!(comments_closed_at: Time.current)
      expect(described_class.permission(user: viewer, target: workout)).to eq(:closed)
    end

    it "reads a received note through its policy and the origin's profile" do
      note = create(:remote_note)
      closed = create(:remote_note, representation: note.representation.merge("comments_closed" => true))

      expect(described_class.permission(user: viewer, target: note)).to eq(:allowed)
      expect(described_class.permission(user: viewer, target: closed)).to eq(:closed)
      expect(described_class.permission(user: nil, target: note)).to eq(:denied)

      allow(Allure::Federation::Config).to receive(:enabled?).and_return(false)
      expect(described_class.permission(user: viewer, target: note)).to eq(:denied)
    end
  end

  # PLAN_COMMENTS.md §8.1, §8.2: the outbound intent each comment carries.
  describe "federation" do
    let(:host) { create(:actor, uri: "https://remote.example/users/demo") }
    let(:note) { create(:remote_note, actor: host) }

    it "sends a comment on a received note to its origin alone" do
      comment = post(target: note)

      event = FederationOutboxEvent.find_by!(activity_uri: comment.activity_uri)
      expect(event.activity_type).to eq("Create")
      expect(event.subject_type).to eq("Actor")
      expect(event.subject_id).to eq(viewer.actor.id)
      expect(event.object_uri).to eq(comment.uri)
      expect(event.audience).to eq("to" => [ host.uri ], "cc" => [])
      expect(event.payload["object"]).to include(
        "id" => comment.uri, "type" => "Note", "inReplyTo" => note.object_uri, "to" => [ host.uri ]
      )
      expect(comment.remote_note).to eq(note)
      expect(comment.audience).to eq("public")
    end

    it "answers a comment on a received note under it" do
      root = create(:comment, workout: nil, remote_note: note, actor: host, uri: "https://remote.example/api/v1/comment/r1",
                              in_reply_to_uri: note.object_uri)

      reply = post(target: note, parent: root)

      expect(reply.parent).to eq(root)
      expect(FederationOutboxEvent.find_by!(activity_uri: reply.activity_uri).payload.dig("object", "inReplyTo"))
        .to eq(root.uri)
    end

    it "sends the owner's comment to the publication's recipients as a secondary event" do
      publication = publish!

      comment = post(user: owner)

      event = FederationOutboxEvent.find_by!(activity_uri: comment.activity_uri)
      expect(event.subject_type).to eq("WorkoutPublication")
      expect(event.workout_publication_id).to eq(publication.id)
      expect(event.object_uri).to eq(comment.uri)
      expect(event.audience).to eq(
        "to" => [ Federation::Serializers::WorkoutNote::PUBLIC_AUDIENCE ], "cc" => [ "#{owner.actor.uri}/followers" ]
      )
    end

    # PLAN_COMMENTS.md §6.6: the owner relays a member's comment on a public
    # workout; a followers thread is never relayed.
    it "relays a member's comment on a public workout through the owner" do
      publication = publish!

      comment = post

      expect(comment.activity_uri).to be_nil
      announce = FederationOutboxEvent.find_by!(activity_type: "Announce")
      expect(announce.actor).to eq(owner.actor)
      expect(announce.activity_uri).to eq(Federation::Outbox::CommentAnnounce.activity_uri_for(comment, owner.actor))
      expect(announce.workout_publication_id).to eq(publication.id)
      expect(announce.payload["object"]).to include("id" => comment.uri, "attributedTo" => viewer.actor.uri)
      expect(announce.audience).to eq(
        "to" => [ Federation::Serializers::WorkoutNote::PUBLIC_AUDIENCE ], "cc" => [ "#{owner.actor.uri}/followers" ]
      )
    end

    it "never relays a followers thread" do
      allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(true)
      PublishingProfile.ensure_built_ins_for!(owner)
      publish!(profile: owner.publishing_profiles.find_by!(built_in_key: "followers"))
      owner_actor = Federation::ActorProvisioner.new(user: owner).call!
      viewer_actor = Federation::ActorProvisioner.new(user: viewer).call!
      create(:following, :accepted, follower_actor: viewer_actor, followed_actor: owner_actor)

      post

      expect(FederationOutboxEvent.where(activity_type: "Announce")).to be_empty
    end

    it "queues the expansion after commit" do
      expect { post(target: note) }.to have_enqueued_job(Federation::ExpandOutboxEventJob)
    end
  end
end
