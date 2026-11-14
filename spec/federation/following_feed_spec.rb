# frozen_string_literal: true

require "rails_helper"

RSpec.describe Federation::FollowingFeed do
  let(:viewer) { create(:user) }
  let(:viewer_actor) { Federation::ActorProvisioner.new(user: viewer).call! }
  let(:followed) { create(:user, username: "followed") }
  let(:followed_actor) { Federation::ActorProvisioner.new(user: followed).call! }
  let(:stranger) { create(:user, username: "stranger") }
  let(:stranger_actor) { Federation::ActorProvisioner.new(user: stranger).call! }
  let(:remote_author) { create(:actor, uri: "https://remote.example/users/demo") }

  def feed(include_public: false) = described_class.new(actor: viewer_actor, include_public:)
  def items(limit: nil, offset: nil, include_public: false)
    stream = feed(include_public:)
    relation = stream.relation
    relation = relation.limit(limit) if limit
    relation = relation.offset(offset) if offset
    stream.items_for(relation)
  end

  def local_workout(user:, published_at:)
    workout = create(:workout, user:)
    PublishingProfile.ensure_built_ins_for!(user)
    profile = user.publishing_profiles.find_by!(built_in_key: "public")
    create(:workout_publication, workout:, publishing_profile: profile, published_at:)
    workout
  end

  def followers_workout(user:, published_at:)
    workout = create(:workout, user:)
    PublishingProfile.ensure_built_ins_for!(user)
    profile = user.publishing_profiles.find_by!(built_in_key: "followers")
    create(:workout_publication, workout:, publishing_profile: profile, published_at:)
    workout
  end

  def remote_note(published_at:, actor: remote_author, recipient: viewer_actor, **attributes)
    note = create(:remote_note, actor:, published_at:, **attributes)
    create(:remote_note_recipient, remote_note: note, recipient_actor: recipient)
    note
  end

  before do
    create(:following, :accepted, follower_actor: viewer_actor, followed_actor: followed_actor)
  end

  it "merges followed local publications and entitled remote notes by date" do
    older = local_workout(user: followed, published_at: 2.hours.ago)
    middle = remote_note(published_at: 1.hour.ago)
    newer = local_workout(user: followed, published_at: 10.minutes.ago)

    expect(items.map { |item| item.record.id }).to eq([ newer.id, middle.id, older.id ])
    expect(items.map(&:kind)).to eq(%w[local remote local])
  end

  it "excludes accounts the viewer does not follow" do
    local_workout(user: stranger, published_at: 1.hour.ago)

    expect(items).to be_empty
  end

  it "excludes a remote note entitled to another local account" do
    remote_note(published_at: 1.hour.ago, recipient: stranger_actor)

    expect(items).to be_empty
  end

  it "excludes withdrawn entitlements, deleted notes, and tombstoned actors" do
    withdrawn = remote_note(published_at: 3.hours.ago)
    withdrawn.recipients.find_by!(recipient_actor: viewer_actor).withdraw!(reason: "unfollow")
    deleted = remote_note(published_at: 2.hours.ago)
    deleted.mark_deleted!
    tombstoned_remote = remote_note(published_at: 1.hour.ago)
    tombstoned_remote.actor.tombstone!
    local_workout(user: followed, published_at: 30.minutes.ago)
    followed_actor.tombstone!

    expect(items).to be_empty
  end

  it "paginates without overlap or gaps" do
    5.times { |index| local_workout(user: followed, published_at: (index + 1).hours.ago) }

    first = items(limit: 2, offset: 0)
    second = items(limit: 2, offset: 2)

    expect(first.length).to eq(2)
    expect(second.length).to eq(2)
    expect(first.map { |item| item.record.id } & second.map { |item| item.record.id }).to be_empty
  end

  it "reports whether the viewer follows anyone" do
    expect(feed.follows_anyone?).to be(true)

    Following.accepted_following_of(viewer_actor).each(&:undo!)

    expect(feed.follows_anyone?).to be(false)
  end

  describe "with a deactivated owner (PLAN_ACCOUNT.md §4.2)" do
    # The window hides an account's publications from every reader until the
    # purge withdraws them, the feed included: its union is raw SQL, not
    # `WorkoutPublication.visible_to`.
    def schedule_deletion(user)
      user.update!(deletion_requested_at: Time.current, deletion_scheduled_at: 1.day.from_now,
                   deletion_requested_by: "self")
    end

    it "hides a followed account's publications" do
      local_workout(user: followed, published_at: 2.hours.ago)
      schedule_deletion(followed)

      expect(items).to be_empty
    end

    it "hides a deactivated stranger's publication from the public stream" do
      local_workout(user: stranger, published_at: 1.hour.ago)
      schedule_deletion(stranger)

      expect(items(include_public: true)).to be_empty
    end
  end

  describe "with a followed author's audiences" do
    it "includes a followers publication while the restricted audience is enabled" do
      allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(true)
      public_workout = local_workout(user: followed, published_at: 2.hours.ago)
      followers = followers_workout(user: followed, published_at: 1.hour.ago)

      expect(items.map { |item| item.record.id }).to eq([ followers.id, public_workout.id ])
    end

    it "includes a followers publication while the restricted audience is disabled" do
      allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(false)
      followers = followers_workout(user: followed, published_at: 1.hour.ago)

      expect(items.map { |item| item.record.id }).to eq([ followers.id ])
    end

    it "never includes a non-followed author's followers publication" do
      allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(true)
      followers_workout(user: stranger, published_at: 1.hour.ago)

      expect(items).to be_empty
    end

    it "excludes a followed author's followers publication after unfollow" do
      allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(true)
      followers_workout(user: followed, published_at: 1.hour.ago)
      Following.accepted_following_of(viewer_actor).each(&:undo!)

      expect(items).to be_empty
    end
  end

  describe "with the viewer's own publications" do
    it "always includes them, whatever the audience" do
      own_public = local_workout(user: viewer, published_at: 2.hours.ago)
      own_followers = followers_workout(user: viewer, published_at: 1.hour.ago)

      expect(items.map { |item| item.record.id }).to eq([ own_followers.id, own_public.id ])
    end

    it "lists the viewer's own publication once when Public is on" do
      own = local_workout(user: viewer, published_at: 2.hours.ago)
      stranger_workout = local_workout(user: stranger, published_at: 1.hour.ago)

      result = items(include_public: true)

      expect(result.map { |item| item.record.id }).to eq([ stranger_workout.id, own.id ])
      expect(result.count { |item| item.record.id == own.id }).to eq(1)
    end
  end

  describe "with include_public" do
    it "adds instance public publications without duplicating a followed author" do
      followed_workout = local_workout(user: followed, published_at: 2.hours.ago)
      stranger_workout = local_workout(user: stranger, published_at: 1.hour.ago)

      result = items(include_public: true)

      expect(result.map { |item| item.record.id }).to eq([ stranger_workout.id, followed_workout.id ])
      expect(result.count { |item| item.record.user_id == followed.id }).to eq(1)
    end

    it "keeps entitled remote notes in the extended stream" do
      note = remote_note(published_at: 1.hour.ago)
      stranger_workout = local_workout(user: stranger, published_at: 2.hours.ago)

      expect(items(include_public: true).map { |item| item.record.id }).to eq([ note.id, stranger_workout.id ])
    end
  end
end
