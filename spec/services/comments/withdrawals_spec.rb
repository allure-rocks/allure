# frozen_string_literal: true

require "rails_helper"

# The ways a comment leaves its thread (docs/dev/COMMENTS.md):
# its author deletes it, the workout's owner removes it, an account deletion
# removes every comment it wrote, and the owner closes the thread.
RSpec.describe "Comment withdrawals" do
  let(:owner) { create(:user) }
  let(:author) { create(:user) }
  let(:workout) { create(:workout, user: owner) }

  before { create(:workout_publication, workout:, publishing_profile: public_publishing_profile_for(owner)) }

  def comment_by(user, parent: nil)
    Comments::Post.new(user:, target: workout, body: "Bravo", parent_id: parent&.to_param).call!
  end

  describe Comments::Delete do
    it "lets the author delete their comment and withdraws its notices, idempotently" do
      comment = comment_by(author)

      expect { described_class.new(user: author, comment:).call! }
        .to change { Notification.where(kind: "comment", subject: comment).count }.from(1).to(0)
      expect(comment.reload).to be_deleted

      expect { described_class.new(user: author, comment:).call! }.not_to(change { comment.reload.deleted_at })
    end

    it "refuses anyone but the author, the owner included" do
      comment = comment_by(author)

      expect { described_class.new(user: owner, comment:).call! }.to raise_error(described_class::NotAllowed)
      expect { described_class.new(user: nil, comment:).call! }.to raise_error(described_class::NotAllowed)
    end
  end

  describe Comments::Remove do
    it "lets the owner remove someone else's comment and withdraws its notices" do
      root = comment_by(author)
      reply = comment_by(create(:user), parent: root)

      described_class.new(user: owner, comment: root).call!

      expect(root.reload).to be_removed
      expect(root.removal_reason).to eq("owner")
      expect(reply.reload).to be_active
      expect(Notification.where(kind: "comment", subject: root)).to be_empty
    end

    it "refuses the author, a stranger, and the owner's own comment" do
      comment = comment_by(author)
      own = comment_by(owner)

      expect { described_class.new(user: author, comment:).call! }.to raise_error(described_class::NotAllowed)
      expect { described_class.new(user: create(:user), comment:).call! }.to raise_error(described_class::NotAllowed)
      expect { described_class.new(user: owner, comment: own).call! }.to raise_error(described_class::NotAllowed)
    end
  end

  describe Comments::Close do
    it "closes and reopens the thread for the owner only" do
      described_class.new(user: owner, workout:, closed: true).call!
      closed_at = workout.reload.comments_closed_at

      expect(closed_at).to be_present
      described_class.new(user: owner, workout:, closed: true).call!
      expect(workout.reload.comments_closed_at).to eq(closed_at)

      described_class.new(user: owner, workout:, closed: false).call!
      expect(workout.reload.comments_closed_at).to be_nil

      expect { described_class.new(user: author, workout:, closed: true).call! }
        .to raise_error(described_class::NotAllowed)
    end
  end

  describe Comments::AuthorRemoval do
    it "removes every active comment of the actors with their notices and leaves the rest" do
      first = comment_by(author)
      second = comment_by(author, parent: comment_by(owner))
      deleted = comment_by(author).tap(&:mark_deleted!)
      kept = comment_by(create(:user))

      expect(described_class.new(actors: author.actor, reason: "actor_deleted").call!).to eq(2)

      expect([ first, second ].map { |comment| comment.reload.status }).to all(eq("removed"))
      expect(first.removal_reason).to eq("actor_deleted")
      expect(first.body).to eq("")
      expect(deleted.reload).to be_deleted
      expect(kept.reload).to be_active
      expect(Notification.where(kind: "comment", subject: [ first, second ])).to be_empty
    end

    it "takes a blocked author's comments out without erasing them" do
      blocked = comment_by(author)

      described_class.new(actors: author.actor, reason: "blocked").call!

      expect(blocked.reload).to be_removed
      expect(blocked.body).to eq("Bravo")
    end

    it "redacts the Creates of a deleted account's comments" do
      host = create(:actor, uri: "https://remote.example/users/demo")
      comment = Comments::Post.new(user: author, target: create(:remote_note, actor: host), body: "Adieu").call!
      create_event = FederationOutboxEvent.find_by!(activity_uri: comment.activity_uri)

      described_class.new(actors: author.actor, reason: "actor_deleted").call!

      expect(create_event.reload.payload["redacted"]).to be(true)
      expect(create_event.payload.to_json).not_to include("Adieu")
    end
  end

  # docs/dev/COMMENTS.md: the withdrawals that travel.
  describe "federated withdrawals" do
    let(:host) { create(:actor, uri: "https://remote.example/users/demo") }
    let(:note) { create(:remote_note, actor: host) }

    def attempt!(event, recipient_uri)
      delivery = event.deliveries.create!(inbox_url: "#{recipient_uri}/inbox", status: "delivered", attempts: 1)
      delivery.recipients.create!(actor_uri: recipient_uri, status: "authorized")
    end

    it "sends the author's Delete where the comment's Create went and keeps the words nowhere" do
      comment = Comments::Post.new(user: author, target: note, body: "Oups").call!
      create_event = FederationOutboxEvent.find_by!(activity_uri: comment.activity_uri)
      attempt!(create_event, host.uri)

      Comments::Delete.new(user: author, comment:).call!

      delete = FederationOutboxEvent.find_by!(activity_type: "Delete", object_uri: comment.uri)
      expect(delete.audience).to eq("recipients" => [ host.uri ], "to" => [ host.uri ], "cc" => [])
      expect(delete.payload["object"]).to include("id" => comment.uri, "type" => "Tombstone", "formerType" => "Note")
      expect(create_event.reload.payload["redacted"]).to be(true)
      expect(create_event.payload.to_json).not_to include("Oups")
      expect(comment.reload.body).to eq("")
    end

    it "sends nothing for a Create that never left and cancels it" do
      comment = Comments::Post.new(user: author, target: note, body: "Oups").call!
      create_event = FederationOutboxEvent.find_by!(activity_uri: comment.activity_uri)
      pending = create_event.deliveries.create!(inbox_url: "#{host.uri}/inbox", status: "pending")

      Comments::Delete.new(user: author, comment:).call!

      expect(FederationOutboxEvent.where(activity_type: "Delete")).to be_empty
      expect(pending.reload).to be_cancelled
      expect(Federation::Outbox::CommentSendability.sendable?(create_event)).to be(false)
    end

    it "tells a remote author the owner removed their comment" do
      remote_comment = create(:comment, workout:, actor: host, uri: "https://remote.example/api/v1/comment/c1",
                                        activity_uri: "https://remote.example/api/v1/comment/c1/activities/create-1")

      Comments::Remove.new(user: owner, comment: remote_comment).call!

      reject = FederationOutboxEvent.find_by!(activity_type: "Reject")
      expect(reject.actor).to eq(owner.actor)
      expect(reject.payload).to include(
        "object" => remote_comment.activity_uri, "_allure_reason" => "removed", "to" => [ host.uri ]
      )
    end

    it "stops relaying a removed comment and undoes the relay where it went" do
      comment = comment_by(author)
      announce = FederationOutboxEvent.find_by!(activity_type: "Announce")
      attempt!(announce, host.uri)
      unsent = comment_by(create(:user))
      unsent_announce = FederationOutboxEvent.where(activity_type: "Announce").order(:id).last
      pending = unsent_announce.deliveries.create!(inbox_url: "#{host.uri}/inbox", status: "pending")

      Comments::Remove.new(user: owner, comment:).call!
      Comments::Remove.new(user: owner, comment: unsent).call!

      undo = FederationOutboxEvent.find_by!(activity_type: "Undo")
      expect(undo.actor).to eq(owner.actor)
      expect(undo.audience).to eq("recipients" => [ host.uri ], "to" => [ host.uri ], "cc" => [])
      expect(undo.payload["object"]).to eq("type" => "Announce", "id" => announce.activity_uri, "object" => comment.uri)
      expect(announce.reload.payload["redacted"]).to be(true)
      expect(pending.reload).to be_cancelled
      expect(FederationOutboxEvent.where(activity_type: "Undo").count).to eq(1)
    end

    it "undoes the relays of a deleted account's comments once the deletion commits" do
      comment = comment_by(author)
      attempt!(FederationOutboxEvent.find_by!(activity_type: "Announce"), host.uri)

      Users::DeleteAccount.new(user: author).call!

      undo = FederationOutboxEvent.find_by!(activity_type: "Undo")
      expect(undo.actor).to eq(owner.actor)
      expect(undo.payload.dig("object", "object")).to eq(comment.uri)
      expect(Federation::ExpandOutboxEventJob).to have_been_enqueued.with(undo)
    end
  end

  it "removes a deleted account's comments from other workouts" do
    comment = comment_by(author)

    Users::DeleteAccount.new(user: author).call!

    expect(comment.reload).to be_removed
    expect(comment.removal_reason).to eq("actor_deleted")
  end
end
