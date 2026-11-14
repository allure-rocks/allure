# frozen_string_literal: true

require "rails_helper"

# The relay as a reader receives it (PLAN_COMMENTS.md §7.5): the thread host
# announces the comments it accepted on its public publication; a third
# party's comment is checked against its author's own copy, this instance's
# own comment is confirmed, and the host's Undo takes a relayed comment out.
RSpec.describe "Relayed comments" do
  let(:reader) { create(:user) }
  let(:reader_actor) { Federation::ActorProvisioner.new(user: reader).call! }
  let!(:host) do
    create(:actor, uri: "https://remote.example/users/demo",
                   raw: { "followers" => "https://remote.example/users/demo/followers" })
  end
  let!(:author) do
    create(:actor, uri: "https://third.example/users/eve", display_name: "Eve",
                   last_fetched_at: Time.current, inbox_url: "https://third.example/users/eve/inbox")
  end
  let(:note) { create(:remote_note, actor: host) }
  let(:comment_uri) { "https://third.example/api/v1/comment/e1" }
  let(:client) { instance_double(Federation::Transport::Client) }

  before do
    create(:remote_note_recipient, remote_note: note, recipient_actor: reader_actor)
    allow(client).to receive(:validate_url)
  end

  def eve_comment(id: comment_uri, in_reply_to: note.object_uri, content: "Quelle vue !", context: note.object_uri)
    { "id" => id, "type" => "Note", "attributedTo" => author.uri, "inReplyTo" => in_reply_to, "context" => context,
      "content" => content, "published" => "2026-10-05T10:00:00Z", "to" => [ host.uri ], "cc" => [] }
  end

  def announce(object, id: "https://remote.example/users/demo/activities/#{SecureRandom.hex(4)}", actor: host.uri)
    { "id" => id, "type" => "Announce", "actor" => actor, "object" => object,
      "to" => [ Federation::Serializers::WorkoutNote::PUBLIC_AUDIENCE ], "cc" => [ "#{host.uri}/followers" ] }
  end

  def inbox_item(activity)
    create(:federation_inbox_item, recipient_actor: reader_actor, activity_uri: activity.fetch("id"),
                                   activity_type: activity.fetch("type"), actor_uri: activity.fetch("actor"), raw: activity)
  end

  def relay(activity)
    Federation::Inbox::CommentRelay.new(item: inbox_item(activity), activity:, client:).call!
  end

  def author_answers(status, document = nil)
    allow(client).to receive(:get).and_return(
      Federation::Transport::Client::Response.new(status, {}, document&.to_json.to_s, URI(comment_uri))
    )
  end

  it "stores a third party's comment once its author's instance confirms it" do
    author_answers(200, eve_comment)

    comment = relay(announce(eve_comment))

    expect(comment).to have_attributes(remote_note: note, actor: author, relayed_by_actor: host, audience: "public")
    expect(comment.confirmed_at).to be_present
    expect(comment.relay_activity_uri).to be_present
    expect(client).to have_received(:get).with(comment_uri, hash_including(headers: hash_including("Signature")))
  end

  it "refuses words the author's instance does not confirm" do
    author_answers(200, eve_comment(content: "Autre chose"))
    expect { relay(announce(eve_comment)) }.to raise_error(Federation::Inbox::Rejected, /does not match/)

    author_answers(404)
    expect { relay(announce(eve_comment)) }.to raise_error(Federation::Inbox::Rejected, /does not confirm/)
    expect(Comment.count).to eq(0)
  end

  it "tries again later when the author's instance is unreachable" do
    author_answers(503)

    expect { relay(announce(eve_comment)) }.to raise_error(Federation::CommentFetcher::Unavailable)
  end

  it "confirms this instance's own comment without fetching it" do
    mine = Comments::Post.new(user: reader, target: note, body: "Merci").call!
    allow(client).to receive(:get)

    activity = announce(Federation::Serializers::CommentNote.new(comment: mine).call)
    relay(activity)

    expect(mine.reload.confirmed_at).to be_present
    expect(mine.relay_activity_uri).to eq(activity["id"])
    expect(client).not_to have_received(:get)
  end

  it "keeps a reply to an unknown comment on its thread and attaches it when the comment arrives" do
    root_uri = "https://third.example/api/v1/comment/e0"
    reply = eve_comment(id: "https://third.example/api/v1/comment/e2", in_reply_to: root_uri, content: "Moi aussi")
    root = eve_comment(id: root_uri, content: "Qui vient ?")
    allow(client).to receive(:get) do |url, **|
      document = url == root_uri ? root : reply
      Federation::Transport::Client::Response.new(200, {}, document.to_json, URI(url))
    end

    orphan = relay(announce(reply))
    expect([ orphan.parent, orphan.warnings ]).to eq([ nil, [ "parent comment not yet received" ] ])

    adopted_by = relay(announce(root))
    expect(orphan.reload.parent).to eq(adopted_by)
  end

  it "notifies the local author a relayed reply answers" do
    mine = Comments::Post.new(user: reader, target: note, body: "Question ?").call!
    answer = eve_comment(in_reply_to: mine.uri)
    author_answers(200, answer)

    relayed = relay(announce(answer))

    expect(relayed.parent).to eq(mine)
    expect(Notification.where(user: reader, kind: "comment", subject: relayed)).to exist
  end

  it "accepts a relay from the thread host alone, on a public thread, from an unblocked author" do
    author_answers(200, eve_comment)
    create(:actor, uri: "https://remote.example/users/mallory")

    expect { relay(announce(eve_comment, actor: "https://remote.example/users/mallory")) }
      .to raise_error(Federation::Inbox::Rejected, /only the thread host/)

    followers_note = create(:remote_note, actor: host, audience: "followers")
    create(:remote_note_recipient, remote_note: followers_note, recipient_actor: reader_actor)
    expect { relay(announce(eve_comment(in_reply_to: followers_note.object_uri))) }
      .to raise_error(Federation::Inbox::Rejected, /only a public thread/)

    create(:federation_actor_block, actor_uri: author.uri)
    expect { relay(announce(eve_comment)) }.to raise_error(Federation::Inbox::Rejected, /blocked/)
  end

  it "bounds a received thread like a hosted one" do
    stub_const("Comment::MAX_ACTIVE_PER_THREAD", 1)
    Comments::Post.new(user: reader, target: note, body: "Premier").call!
    author_answers(200, eve_comment)

    expect { relay(announce(eve_comment)) }.to raise_error(Federation::Inbox::Rejected, /full/)
  end

  it "is idempotent" do
    author_answers(200, eve_comment)
    first = relay(announce(eve_comment))

    expect(relay(announce(eve_comment))).to eq(first)
    expect(Comment.count).to eq(1)
  end

  describe "the host's Undo" do
    def deliver(activity)
      item = inbox_item(activity)
      Federation::ProcessInboxItemJob.perform_now(item)
      item.reload
    end

    def undo(relayed_activity_uri:, object:, actor: host.uri)
      { "id" => "https://remote.example/users/demo/activities/undo-#{SecureRandom.hex(4)}", "type" => "Undo",
        "actor" => actor, "object" => { "type" => "Announce", "id" => relayed_activity_uri, "object" => object },
        "to" => [ reader_actor.uri ] }
    end

    it "takes a third party's relayed comment out with its words" do
      author_answers(200, eve_comment)
      relayed = relay(announce(eve_comment))

      expect(deliver(undo(relayed_activity_uri: relayed.relay_activity_uri, object: relayed.uri))).to be_processed

      expect(relayed.reload).to be_removed
      expect([ relayed.removal_reason, relayed.body ]).to eq([ "unknown", "" ])
    end

    it "marks this instance's own comment removed by the owner" do
      mine = Comments::Post.new(user: reader, target: note, body: "Merci").call!
      activity = announce(Federation::Serializers::CommentNote.new(comment: mine).call)
      relay(activity)

      deliver(undo(relayed_activity_uri: activity["id"], object: mine.uri))

      expect(mine.reload).to be_removed
      expect([ mine.removal_reason, mine.body ]).to eq([ "owner", "Merci" ])
    end

    it "accepts the Undo from the host alone and ignores an unknown relay" do
      author_answers(200, eve_comment)
      relayed = relay(announce(eve_comment))
      create(:actor, uri: "https://remote.example/users/mallory")

      forged = undo(relayed_activity_uri: relayed.relay_activity_uri, object: relayed.uri,
                    actor: "https://remote.example/users/mallory")
      expect(deliver(forged)).to be_rejected
      expect(relayed.reload).to be_active

      expect(deliver(undo(relayed_activity_uri: "https://remote.example/x", object: "https://third.example/nope")))
        .to be_processed
    end
  end
end
