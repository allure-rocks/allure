# frozen_string_literal: true

require "rails_helper"

RSpec.describe Federation::Serializers::CommentNote do
  let(:owner) { create(:user) }
  let(:reader) { create(:user) }
  let(:workout) { create(:workout, user: owner) }

  before do
    create(:workout_publication, workout:, publishing_profile: public_publishing_profile_for(owner))
  end

  def post(user, target: workout, body: "Belle sortie !\nOn y retourne ? <b>non</b>")
    Comments::Post.new(user:, target:, body:).call!
  end

  it "serializes a local comment as a plain Note answering its thread" do
    comment = post(reader)

    note = described_class.new(comment:).call

    expect(note).to eq(
      "@context" => "https://www.w3.org/ns/activitystreams",
      "id" => comment.uri,
      "type" => "Note",
      "attributedTo" => reader.actor.uri,
      "inReplyTo" => workout.active_publications.first.object_uri,
      "context" => workout.active_publications.first.object_uri,
      "content" => "Belle sortie !<br>On y retourne ? &lt;b&gt;non&lt;/b&gt;",
      "published" => comment.published_at.utc.iso8601,
      "to" => [ owner.actor.uri ],
      "cc" => []
    )
  end

  it "addresses the owner's comment to the publication's audience" do
    note = described_class.new(comment: post(owner)).call

    expect(note["to"]).to eq([ Federation::Serializers::WorkoutNote::PUBLIC_AUDIENCE ])
    expect(note["cc"]).to eq([ "#{owner.actor.uri}/followers" ])
  end

  it "addresses the owner's comment on a followers publication to the followers alone" do
    allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(true)
    other = create(:workout, user: owner)
    create(:workout_publication, workout: other,
                                 publishing_profile: owner.publishing_profiles.find_by!(built_in_key: "followers"))

    note = described_class.new(comment: post(owner, target: other)).call

    expect(note["to"]).to eq([ "#{owner.actor.uri}/followers" ])
    expect(note["cc"]).to eq([])
  end

  it "answers the parent comment and addresses a received note's host" do
    host = create(:actor, uri: "https://remote.example/users/demo")
    received = create(:remote_note, actor: host)
    root = Comments::Post.new(user: reader, target: received, body: "Première").call!
    reply = Comments::Post.new(user: reader, target: received, body: "Suite", parent_id: root.to_param).call!

    note = described_class.new(comment: reply).call

    expect(note["inReplyTo"]).to eq(root.uri)
    expect(note["context"]).to eq(received.object_uri)
    expect(note["to"]).to eq([ host.uri ])
  end

  # PLAN_COMMENTS.md §7.2: a relayed comment can wait as a root for the
  # comment it answers; a reply to it still names the received note.
  it "names the received note as the context of a reply to a waiting comment" do
    host = create(:actor, uri: "https://remote.example/users/demo")
    received = create(:remote_note, actor: host)
    waiting = create(:comment, workout: nil, remote_note: received, actor: create(:actor),
                               uri: "https://third.example/api/v1/comment/w1",
                               in_reply_to_uri: "https://third.example/api/v1/comment/unknown")
    reply = Comments::Post.new(user: reader, target: received, body: "Moi aussi", parent_id: waiting.to_param).call!

    expect(described_class.new(comment: reply).call["context"]).to eq(received.object_uri)
  end

  it "never serializes another instance's comment" do
    remote = create(:comment, workout:, actor: create(:actor), uri: "https://remote.example/api/v1/comment/x")

    expect { described_class.new(comment: remote).call }.to raise_error(described_class::Unavailable)
  end
end
