# frozen_string_literal: true

require "rails_helper"

RSpec.describe Comments::Listing do
  let(:owner) { create(:user) }
  let(:workout) { create(:workout, user: owner) }
  let(:alice) { create(:user) }
  let(:bob) { create(:user) }

  before { create(:workout_publication, workout:, publishing_profile: public_publishing_profile_for(owner)) }

  def comment_by(user, parent: nil, body: "Bravo")
    Comments::Post.new(user:, target: workout, body:, parent_id: parent&.to_param).call!
  end

  def listing(viewer: nil) = described_class.new(target: workout, viewer:).call

  it "orders roots and their replies by posting time" do
    first = comment_by(alice, body: "Premier")
    second = comment_by(bob, body: "Second")
    reply = comment_by(owner, parent: first, body: "Réponse")

    result = listing

    expect(result.entries.map(&:comment)).to eq([ first, second ])
    expect(result.entries.first.replies).to eq([ reply ])
    expect(result.active_count).to eq(3)
  end

  it "keeps a withdrawn root as a stub only while it has visible replies" do
    with_reply = comment_by(alice)
    comment_by(bob, parent: with_reply)
    alone = comment_by(bob)
    with_reply.mark_deleted!
    alone.mark_deleted!

    entries = listing.entries

    expect(entries.size).to eq(1)
    expect(entries.first).to be_stub
    expect(entries.first.comment).to eq(with_reply)
  end

  it "shows a removed comment to its author only" do
    removed = comment_by(alice)
    Comments::Remove.new(user: owner, comment: removed).call!

    expect(listing(viewer: alice.actor).entries.map(&:comment)).to eq([ removed ])
    expect(listing(viewer: bob.reload.actor).entries).to be_empty
    expect(listing.active_count).to eq(0)
  end

  it "loads a long thread and its authors in a fixed number of queries" do
    comment_by(alice)
    comment_by(bob)
    few = count_queries { listing.entries.each { |entry| entry.comment.actor.user&.avatar_image? } }
    3.times { comment_by(create(:user)) }

    many = count_queries { listing.entries.each { |entry| entry.comment.actor.user&.avatar_image? } }

    expect(many).to eq(few)
  end
end

RSpec.describe Comments::Counts do
  it "counts active comments per target in one query per target class" do
    owner = create(:user)
    busy = create(:workout, user: owner)
    quiet = create(:workout, user: owner)
    note = create(:remote_note)
    [ busy, quiet ].each do |workout|
      create(:workout_publication, workout:, publishing_profile: public_publishing_profile_for(owner))
    end
    2.times { Comments::Post.new(user: create(:user), target: busy, body: "Oui").call! }
    Comments::Post.new(user: create(:user), target: busy, body: "Non").call!.mark_deleted!

    counts = nil
    queries = count_queries { counts = described_class.new(targets: [ busy, quiet, note ], viewer: owner).call }

    expect(counts).to eq(busy => 2, quiet => 0, note => 0)
    expect(queries).to eq(2)
  end
end
