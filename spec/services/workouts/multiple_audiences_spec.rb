# frozen_string_literal: true

require "rails_helper"

# One live publication per audience (docs/dev/PUBLISHING.md): a workout published
# to its followers and to the public at once, each reader served the narrowest
# version they are entitled to.
RSpec.describe "Workout publications per audience" do
  let(:owner) { create(:user) }
  let!(:owner_actor) { Federation::ActorProvisioner.new(user: owner).call! }
  let(:workout) { create(:workout, user: owner, title: "Sortie du dimanche") }
  let!(:track_segment) { create(:track_segment, workout:) }
  let(:public_profile) { create(:publishing_profile, :without_endpoint_masks, user: owner) }
  let(:followers_profile) { create(:publishing_profile, :followers, :without_endpoint_masks, user: owner) }
  let(:follower) { create(:user) }
  let(:stranger) { create(:user) }

  before do
    allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(true)
    follower_actor = Federation::ActorProvisioner.new(user: follower).call!
    create(:following, :accepted, follower_actor:, followed_actor: owner_actor)
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  end

  after { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }

  def publish_both!
    [ publish_workout!(user: owner, workout:, profile: public_profile),
      publish_workout!(user: owner, workout:, profile: followers_profile) ]
  end

  describe Workouts::Publisher do
    it "publishes a second audience beside the first" do
      public_publication, followers_publication = publish_both!

      expect(workout.reload.active_publications.map(&:id)).to eq([ followers_publication.id, public_publication.id ])
      expect(workout.live_audiences).to contain_exactly("public", "followers")
    end

    it "refuses a second publication of the same audience" do
      publish_workout!(user: owner, workout:, profile: public_profile)
      other_public = create(:publishing_profile, :custom, :without_endpoint_masks, user: owner, audience: "public")

      expect {
        described_class.new(user: owner, workout:, profile: other_public).call!
      }.to raise_error(Workouts::Publisher::PublicationError, I18n.t("workouts.publish.errors.already_published"))
    end

    it "keeps the audience unique at the database level" do
      publication = publish_workout!(user: owner, workout:, profile: public_profile)
      duplicate = publication.dup
      uuid = SecureRandom.uuid
      duplicate.assign_attributes(uuid:, object_uri: WorkoutPublication.object_uri_for(uuid))

      expect { duplicate.save!(validate: false) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe Workouts::PublicationResolver do
    it "serves a follower the followers version and anyone else the public one" do
      public_publication, followers_publication = publish_both!

      expect(described_class.new(workout:, user: follower).call).to eq(followers_publication)
      expect(described_class.new(workout:, user: stranger).call).to eq(public_publication)
      expect(described_class.new(workout:, user: owner).call).to eq(followers_publication)
      expect(described_class.new(workout:, user: owner, audience: "public").call).to eq(public_publication)
    end

    it "serves nothing to a stranger when only the followers version exists" do
      publish_workout!(user: owner, workout:, profile: followers_profile)

      expect(described_class.new(workout:, user: stranger).call).to be_nil
      expect(workout.viewable_by?(stranger)).to be(false)
      expect(workout.viewable_by?(follower)).to be(true)
    end
  end

  describe Workouts::PublicationReplacement do
    it "replaces one audience and leaves the other publication alone" do
      public_publication, followers_publication = publish_both!

      result = described_class.new(user: owner, workout:, profile: public_profile, publication: public_publication).call!

      expect(result.old_publication).to be_deleted
      expect(result.new_publication.audience).to eq("public")
      expect(followers_publication.reload).to be_active
    end

    it "refuses to move a publication onto an audience another one holds" do
      public_publication, = publish_both!

      expect {
        described_class.new(user: owner, workout:, profile: followers_profile, publication: public_publication).call!
      }.to raise_error(Workouts::Publisher::PublicationError, I18n.t("workouts.publish.errors.audience_taken"))
      expect(public_publication.reload).to be_active
    end
  end

  describe Workouts::PublicationDeletion do
    it "withdraws the named publication only" do
      public_publication, followers_publication = publish_both!

      described_class.new(user: owner, workout:, publication: followers_publication).call!

      expect(followers_publication.reload).to be_deleted
      expect(public_publication.reload).to be_active
    end

    it "withdraws every active publication without a name" do
      publications = publish_both!

      described_class.new(user: owner, workout:).call!

      expect(publications.map { |publication| publication.reload.status }).to all(eq("deleted"))
    end
  end

  describe Workouts::WorkoutDeletion do
    it "withdraws and cancels every audience's publication with the workout" do
      public_publication = publish_workout!(user: owner, workout:, profile: public_profile)
      scheduled = Workouts::Publisher.new(user: owner, workout:, profile: followers_profile, delay: 1.day.to_i).call!

      result = described_class.new(user: owner, workout:).call!

      expect(public_publication.reload).to be_deleted
      expect(scheduled.reload).to be_deleted
      expect(result.delete_events.map(&:object_uri)).to eq([ public_publication.object_uri ])
      expect(FederationOutboxEvent.where(activity_type: "Delete", object_uri: scheduled.object_uri)).to be_empty
    end
  end

  describe "comment threads" do
    it "keeps each audience's thread to its readers" do
      publish_both!

      followers_comment = Comments::Post.new(user: follower, target: workout, body: "Entre nous").call!
      public_comment = Comments::Post.new(user: stranger, target: workout, body: "Bravo").call!
      reply = Comments::Post.new(user: follower, target: workout, body: "Merci", parent_id: public_comment.to_param).call!

      expect(followers_comment.audience).to eq("followers")
      expect(public_comment.audience).to eq("public")
      expect(reply.audience).to eq("public")

      stranger_view = Comments::Listing.new(target: workout, audiences: Workouts::ReadableAudiences.for(user: stranger, workout:)).call
      follower_view = Comments::Listing.new(target: workout, audiences: Workouts::ReadableAudiences.for(user: follower, workout:)).call
      expect(stranger_view.entries.map(&:comment)).to eq([ public_comment ])
      expect(follower_view.entries.map(&:comment)).to contain_exactly(followers_comment, public_comment)
      expect(Comments::Counts.new(targets: [ workout ], viewer: stranger).call.fetch(workout)).to eq(2)
      expect(Comments::Counts.new(targets: [ workout ], viewer: follower).call.fetch(workout)).to eq(3)
    end

    it "lets the owner pick the thread and refuses a reply into an unreadable one" do
      publish_both!

      owner_comment = Comments::Post.new(user: owner, target: workout, body: "Pour tous", audience: "public").call!
      followers_comment = Comments::Post.new(user: follower, target: workout, body: "Entre nous").call!

      expect(owner_comment.audience).to eq("public")
      expect {
        Comments::Post.new(user: stranger, target: workout, body: "Moi aussi", parent_id: followers_comment.to_param).call!
      }.to raise_error(Comments::Post::Invalid)
    end
  end

  describe Federation::FollowingFeed do
    it "shows a follower one item, the followers version" do
      _, followers_publication = publish_both!
      feed = described_class.new(actor: follower.actor)

      items = feed.items_for(feed.relation.to_a)

      expect(items.map(&:publication)).to eq([ followers_publication ])
      expect(items.first.record).to eq(workout)
    end
  end

  describe Federation::Delivery::RecipientAuthorizer do
    def authorize(publication, actor)
      event = FederationOutboxEvent.find_by!(activity_type: "Create", object_uri: publication.object_uri)
      described_class.new(event:, actor:, client: instance_double(Federation::Transport::Client).as_null_object).call
    end

    it "sends a promoted follower the followers Note only, and anyone else the public one" do
      promoted = create(:actor, inbox_url: "https://promoted.example/inbox", capability_profile: "restricted_fetch")
      plain = create(:actor, inbox_url: "https://plain.example/inbox", capability_profile: "public_only")
      [ promoted, plain ].each { |actor| create(:following, :accepted, follower_actor: actor, followed_actor: owner_actor) }
      public_publication, followers_publication = publish_both!

      expect(authorize(followers_publication, promoted).allowed?).to be(true)
      denied = authorize(public_publication, promoted)
      expect(denied.allowed?).to be(false)
      expect(denied.reason).to eq("recipient is served a narrower publication")
      expect(authorize(public_publication, plain).allowed?).to be(true)
    end
  end

  describe Segments::Listing do
    it "ranks an effort once whatever the number of qualifying publications" do
      segment = create(:segment, user: owner, visibility: "public")
      create(:segment_effort, segment:, workout:, user: owner)
      publish_both!

      expect(described_class.for_segment(segment, viewer: owner).count).to eq(1)
    end
  end
end
