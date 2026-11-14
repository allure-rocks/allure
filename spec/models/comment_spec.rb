# frozen_string_literal: true

require "rails_helper"

RSpec.describe Comment do
  let(:workout) { create(:workout) }

  describe "identity" do
    it "mints a local author's URI from its own identifier" do
      comment = create(:comment, workout:)

      expect(comment.uri).to eq("#{Allure::Federation.config.base_url}/api/v1/comment/#{comment.to_param}")
      expect(Comment.find_by_short_id!(comment.to_param)).to eq(comment)
    end

    it "refuses a supplied URI for a local author" do
      comment = build(:comment, workout:, uri: "#{Allure::Federation.config.base_url}/api/v1/comment/other")

      expect(comment).not_to be_valid
      expect(comment.errors[:uri]).to be_present
    end

    it "keeps a remote author's URI" do
      remote = create(:actor)
      comment = create(:comment, workout:, actor: remote, uri: "https://remote.example/api/v1/comment/abc")

      expect(comment.uri).to eq("https://remote.example/api/v1/comment/abc")
    end

    it "never changes its identity, thread, author, or wire parent" do
      comment = create(:comment, workout:)

      expect { comment.update!(uri: "https://elsewhere.example/c") }.to raise_error(ActiveRecord::ReadonlyAttributeError)
      expect { comment.update!(in_reply_to_uri: "https://elsewhere.example/t") }
        .to raise_error(ActiveRecord::ReadonlyAttributeError)
      expect { comment.update!(workout: create(:workout)) }.to raise_error(ActiveRecord::ReadonlyAttributeError)
      expect { comment.update!(actor: create(:actor)) }.to raise_error(ActiveRecord::ReadonlyAttributeError)
    end
  end

  describe "validations" do
    it "requires exactly one thread" do
      note = create(:remote_note)

      expect(build(:comment, workout:)).to be_valid
      expect(build(:comment, workout:, remote_note: note)).not_to be_valid
      expect(build(:comment, workout: nil)).not_to be_valid
    end

    it "bounds the text" do
      expect(build(:comment, workout:, body: "")).not_to be_valid
      expect(build(:comment, workout:, body: "a" * Comment::MAX_BODY_LENGTH)).to be_valid
      expect(build(:comment, workout:, body: "a" * (Comment::MAX_BODY_LENGTH + 1))).not_to be_valid
    end

    it "accepts only known statuses, audiences, and reasons" do
      expect(build(:comment, workout:, audience: "everyone")).not_to be_valid
      expect(build(:comment, workout:, status: "hidden")).not_to be_valid
      expect(build(:comment, :removed, workout:, removal_reason: "spite")).not_to be_valid
    end

    it "requires the instant and the reason of each state" do
      expect(build(:comment, :deleted, workout:)).to be_valid
      expect(build(:comment, workout:, status: "deleted")).not_to be_valid
      expect(build(:comment, :removed, workout:)).to be_valid
      expect(build(:comment, :removed, workout:, removal_reason: nil)).not_to be_valid
      expect(build(:comment, workout:, deleted_at: Time.current)).not_to be_valid
    end

    it "allows one level of replies on the same thread" do
      root = create(:comment, workout:)
      reply = create(:comment, workout:, parent: root, in_reply_to_uri: root.uri)

      expect(reply).to be_reply
      expect(build(:comment, workout:, parent: reply, in_reply_to_uri: reply.uri)).not_to be_valid
      expect(build(:comment, workout: create(:workout), parent: root, in_reply_to_uri: root.uri)).not_to be_valid
    end

    it "never turns a comment with replies into a reply" do
      root = create(:comment, workout:)
      create(:comment, workout:, parent: root, in_reply_to_uri: root.uri)
      other_root = create(:comment, workout:)

      root.parent = other_root

      expect(root).not_to be_valid
    end
  end

  describe "database boundaries" do
    # Each write runs in its own savepoint, so one refusal leaves the example's
    # transaction usable for the next.
    def write(comment, **attributes)
      described_class.transaction { described_class.where(id: comment.id).update_all(attributes) }
    end

    it "enforces the single thread and the text bounds" do
      comment = create(:comment, workout:)
      note = create(:remote_note)

      expect { write(comment, remote_note_id: note.id) }
        .to raise_error(ActiveRecord::StatementInvalid, /comments_single_target/)
      expect { write(comment, body: "") }.to raise_error(ActiveRecord::StatementInvalid, /comments_body_length/)
    end

    it "enforces the state instants" do
      comment = create(:comment, workout:)

      expect { write(comment, status: "removed") }
        .to raise_error(ActiveRecord::StatementInvalid, /comments_removed_state|comments_removal_reason_state/)
    end
  end

  describe "transitions" do
    it "takes the words away with an author's deletion and keeps the identity" do
      comment = create(:comment, workout:, body: "Mes mots", content_html: "<p>Mes mots</p>")

      comment.mark_deleted!

      expect(comment.reload).to be_deleted
      expect([ comment.body, comment.content_html, comment.raw ]).to eq([ "", nil, {} ])
      expect(comment.uri).to be_present
      expect { described_class.transaction { described_class.where(id: create(:comment, workout:).id).update_all(body: "") } }
        .to raise_error(ActiveRecord::StatementInvalid, /comments_body_length/)
    end

    it "deletes, removes, and rejects only from the active state, idempotently" do
      deleted = create(:comment, workout:)
      deleted.mark_deleted!
      deleted.remove!(reason: "owner")

      expect(deleted.reload).to be_deleted
      expect(deleted.removal_reason).to be_nil

      removed = create(:comment, workout:)
      removed.remove!(reason: "owner")
      first_instant = removed.removed_at
      removed.remove!(reason: "blocked")

      expect(removed.reload.removal_reason).to eq("owner")
      expect(removed.removed_at).to eq(first_instant)

      rejected = create(:comment, workout:)
      rejected.reject!(reason: "closed")

      expect(rejected.reload).to be_rejected
      expect(rejected.removal_reason).to eq("closed")
    end
  end

  it "goes with its workout" do
    create(:comment, workout:)

    expect { workout.destroy! }.to change(described_class, :count).by(-1)
  end
end
