# frozen_string_literal: true

require "rails_helper"

# Inbound comments (docs/dev/COMMENTS.md): the host side stores a reader's
# comment on its workout or refuses it with a Reject; the reader side stores
# the host's own comment on the received note; Delete, Reject, blocks and
# author deletions take comments out.
RSpec.describe "Inbound comments" do
  let(:owner) { create(:user, username: "marie") }
  let(:workout) { create(:workout, user: owner, title: "Col du Galibier") }
  let!(:publication) do
    create(:workout_publication, workout:, publishing_profile: public_publishing_profile_for(owner))
  end
  # Admission caches the sender before processing; the cached row is a given.
  let!(:remote) do
    create(:actor, uri: "https://remote.example/users/demo", display_name: "Demo",
                   raw: { "followers" => "https://remote.example/users/demo/followers" })
  end

  def deliver(activity, recipient: owner.actor)
    item = create(:federation_inbox_item, recipient_actor: recipient, activity_uri: activity.fetch("id"),
                                          activity_type: activity.fetch("type"), actor_uri: activity.fetch("actor"),
                                          raw: activity)
    Federation::ProcessInboxItemJob.perform_now(item)
    item.reload
  end

  def comment_activity(in_reply_to: publication.object_uri, id: "https://remote.example/api/v1/comment/c1", **options)
    federation_comment_activity(in_reply_to:, to: owner.actor.uri, id:, **options)
  end

  describe "on a thread this instance hosts" do
    it "stores a reader's comment and tells the owner" do
      item = deliver(comment_activity)

      expect(item).to be_processed
      comment = Comment.find_by!(uri: "https://remote.example/api/v1/comment/c1")
      expect(comment.workout).to eq(workout)
      expect(comment.actor).to eq(remote)
      expect(comment.audience).to eq("public")
      expect(comment.activity_uri).to eq(item.activity_uri)
      expect(comment.content_html).to eq("Belle sortie !<br>On y retourne ?")
      expect(comment.source_domain).to eq("remote.example")
      expect(Notification.where(user: owner, kind: "comment", subject: comment)).to exist
    end

    it "is idempotent and never brings a withdrawn comment back" do
      deliver(comment_activity)
      redelivered = deliver(comment_activity.merge("id" => "https://remote.example/activities/again"))

      expect(redelivered).to be_processed
      expect(Comment.count).to eq(1)

      Comment.last.remove!(reason: "owner")
      again = deliver(comment_activity.merge("id" => "https://remote.example/activities/third"))
      expect(again).to be_rejected
      expect(Comment.last).to be_removed
    end

    it "attaches a reply to its root and flattens an answer to a reply" do
      root = Comments::Post.new(user: owner, target: workout, body: "Qui vient ?").call!
      reader = create(:user)
      local_reply = Comments::Post.new(user: reader, target: workout, body: "Moi", parent_id: root.to_param).call!

      deliver(comment_activity(in_reply_to: root.uri))
      deliver(comment_activity(in_reply_to: local_reply.uri, id: "https://remote.example/api/v1/comment/c2"))

      direct = Comment.find_by!(uri: "https://remote.example/api/v1/comment/c1")
      flattened = Comment.find_by!(uri: "https://remote.example/api/v1/comment/c2")
      expect(direct.parent).to eq(root)
      expect([ flattened.parent, flattened.in_reply_to_uri ]).to eq([ root, local_reply.uri ])
      expect(flattened.warnings).to include("reply depth flattened")
      expect(Notification.where(user: reader, kind: "comment", subject: flattened)).to be_empty
    end

    it "refuses a closed thread with a Reject to the author" do
      workout.update_column(:comments_closed_at, Time.current)

      item = deliver(comment_activity)

      expect(item).to be_rejected
      expect(Comment.count).to eq(0)
      reject = FederationOutboxEvent.find_by!(activity_type: "Reject")
      expect(reject.actor).to eq(owner.actor)
      expect(reject.payload).to include(
        "type" => "Reject", "object" => item.activity_uri, "_allure_reason" => "closed", "to" => [ remote.uri ]
      )
    end

    it "names why it refuses" do
      publication.mark_deleted!
      expect(deliver(comment_activity)).to be_rejected
      expect(FederationOutboxEvent.where(activity_type: "Reject").last.payload["_allure_reason"]).to eq("inactive")

      followers_workout = create(:workout, user: owner)
      allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(true)
      followers = create(:workout_publication, workout: followers_workout,
                                               publishing_profile: owner.publishing_profiles.find_by!(built_in_key: "followers"))
      deliver(comment_activity(in_reply_to: followers.object_uri, id: "https://remote.example/api/v1/comment/c2"))
      expect(FederationOutboxEvent.where(activity_type: "Reject").last.payload["_allure_reason"]).to eq("not_allowed")
    end

    it "refuses a full thread" do
      stub_const("Comment::MAX_ACTIVE_PER_THREAD", 1)
      Comments::Post.new(user: owner, target: workout, body: "Premier").call!

      expect(deliver(comment_activity)).to be_rejected
      expect(FederationOutboxEvent.where(activity_type: "Reject").last.payload["_allure_reason"]).to eq("full")
    end

    it "rejects an unknown thread and a sender that is not the author, without answering" do
      unknown = deliver(comment_activity(in_reply_to: "https://elsewhere.example/api/v1/trail/zzz"))
      forged = comment_activity(id: "https://remote.example/api/v1/comment/c9")
      forged["object"]["attributedTo"] = "https://remote.example/users/eve"

      expect(unknown).to be_rejected
      expect(deliver(forged)).to be_rejected
      expect(FederationOutboxEvent.where(activity_type: "Reject")).to be_empty
    end
  end

  describe "on a received note" do
    let(:reader) { create(:user) }
    let(:reader_actor) { Federation::ActorProvisioner.new(user: reader).call! }
    let(:note) { create(:remote_note, actor: remote) }

    before { create(:remote_note_recipient, remote_note: note, recipient_actor: reader_actor) }

    def host_comment(in_reply_to: note.object_uri, id: "https://remote.example/api/v1/comment/h1")
      federation_comment_activity(in_reply_to:, to: Federation::Serializers::WorkoutNote::PUBLIC_AUDIENCE, id:)
        .tap { |activity| activity["cc"] = [ "https://remote.example/users/demo/followers" ] }
    end

    it "stores the host's own comment and tells the reader it answers" do
      mine = Comments::Post.new(user: reader, target: note, body: "Question ?").call!

      deliver(host_comment(in_reply_to: mine.uri), recipient: reader_actor)

      answer = Comment.find_by!(uri: "https://remote.example/api/v1/comment/h1")
      expect(answer.remote_note).to eq(note)
      expect(answer.parent).to eq(mine)
      expect(Notification.where(user: reader, kind: "comment", subject: answer)).to exist
    end

    it "accepts no one but the host on a received thread" do
      stranger = create(:actor, uri: "https://remote.example/users/eve")
      activity = federation_comment_activity(in_reply_to: note.object_uri, to: reader_actor.uri,
                                             id: "https://remote.example/api/v1/comment/e1", actor: stranger.uri)

      expect(deliver(activity, recipient: reader_actor)).to be_rejected
      expect(Comment.count).to eq(0)
    end

    it "refuses a followers note to an account that does not hold it" do
      note.update_column(:audience, "followers")
      outsider = Federation::ActorProvisioner.new(user: create(:user)).call!

      expect(deliver(host_comment, recipient: outsider)).to be_rejected
    end

    describe "the host's Reject" do
      let!(:mine) { Comments::Post.new(user: reader, target: note, body: "Coucou").call! }

      def reject(reason, actor: remote.uri)
        { "id" => "https://remote.example/activities/reject-#{SecureRandom.hex(4)}", "type" => "Reject",
          "actor" => actor, "object" => mine.activity_uri, "_allure_reason" => reason, "to" => [ reader_actor.uri ] }
      end

      it "marks the comment refused with its reason" do
        expect(deliver(reject("closed"), recipient: reader_actor)).to be_processed

        expect(mine.reload).to be_rejected
        expect(mine.removal_reason).to eq("closed")
      end

      it "marks a removal and degrades an unknown reason" do
        deliver(reject("removed"), recipient: reader_actor)
        expect(mine.reload).to be_removed
        expect(mine.removal_reason).to eq("owner")

        other = Comments::Post.new(user: reader, target: note, body: "Encore").call!
        deliver(reject("whatever").merge("object" => other.activity_uri), recipient: reader_actor)
        expect(other.reload.removal_reason).to eq("unknown")
      end

      it "ignores a Reject from anyone but the host" do
        create(:actor, uri: "https://remote.example/users/eve")

        expect(deliver(reject("closed", actor: "https://remote.example/users/eve"), recipient: reader_actor)).to be_rejected
        expect(mine.reload).to be_active
      end
    end
  end

  describe "withdrawals" do
    before { deliver(comment_activity) }

    let(:comment) { Comment.find_by!(uri: "https://remote.example/api/v1/comment/c1") }

    def delete_activity(object: comment.uri, actor: remote.uri)
      { "id" => "https://remote.example/activities/delete-#{SecureRandom.hex(4)}", "type" => "Delete",
        "actor" => actor, "object" => { "id" => object, "type" => "Tombstone" }, "to" => [ owner.actor.uri ] }
    end

    it "lets the author delete the comment here" do
      expect(deliver(delete_activity)).to be_processed

      expect(comment.reload).to be_deleted
      expect(Notification.where(kind: "comment", subject: comment)).to be_empty
    end

    it "refuses a Delete from another actor and for an unknown comment" do
      create(:actor, uri: "https://remote.example/users/eve")

      expect(deliver(delete_activity(actor: "https://remote.example/users/eve"))).to be_rejected
      expect(deliver(delete_activity(object: "https://remote.example/api/v1/comment/nope"))).to be_rejected
      expect(comment.reload).to be_active
      expect(RemoteNote.count).to eq(0)
    end

    it "removes the comments of a remote author who deleted their account" do
      deliver({ "id" => "https://remote.example/activities/actor-delete", "type" => "Delete", "actor" => remote.uri,
                "object" => { "id" => remote.uri, "type" => "Tombstone" }, "to" => [ owner.actor.uri ] })

      expect(comment.reload).to be_removed
      expect(comment.removal_reason).to eq("actor_deleted")
    end

    it "removes the comments of a blocked author" do
      Federation::Safety::Blocking.new.block_actor!(actor_uri: remote.uri)

      expect(comment.reload).to be_removed
      expect(comment.removal_reason).to eq("blocked")
    end
  end
end
