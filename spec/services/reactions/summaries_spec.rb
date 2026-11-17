# frozen_string_literal: true

require "rails_helper"

# The batched reaction summary (docs/dev/REACTIONS.md): counts and the
# viewer's own type per target, plus the newest reactors per type the pill's
# tooltip names (DESIGN.md §10.17).
RSpec.describe Reactions::Summaries do
  let(:workout) { create(:workout, user: create(:user, display_name: "Marie")) }
  # The owner reads every name; other readers are covered below.
  let(:owner_actor) { Federation::ActorProvisioner.new(user: workout.user).call! }

  def local_actor(display_name)
    create(:local_actor, user: create(:user, display_name:))
  end

  def react(target, actor, kind: "beer", at: Time.current)
    if target.is_a?(Workout)
      create(:reaction, workout: target, actor:, kind:, created_at: at, updated_at: at)
    else
      create(:reaction, :remote_note, remote_note: target, actor:, kind:, created_at: at, updated_at: at)
    end
  end

  describe "#call" do
    it "counts every active type and names the newest reactors first, capped at three" do
      react(workout, local_actor("Éric"), at: 4.hours.ago)
      react(workout, local_actor("Marc"), at: 3.hours.ago)
      react(workout, local_actor("Sophie"), at: 2.hours.ago)
      react(workout, local_actor("Joan"), at: 1.hour.ago)
      react(workout, local_actor("Marc"), kind: "coffee", at: 30.minutes.ago)

      summary = described_class.new(targets: [ workout ], viewer: owner_actor).call.fetch(workout)

      expect(summary.count("beer")).to eq(4)
      expect(summary.count("coffee")).to eq(1)
      expect(summary.reactors("beer").map(&:display_name)).to eq(%w[Joan Sophie Marc])
      expect(summary.reactors("coffee").map(&:display_name)).to eq(%w[Marc])
      expect(summary.reactors("energy")).to be_empty
      expect(summary.mine).to be_nil
    end

    it "carries the viewer's own active type and still names them" do
      viewer = local_actor("Paul")
      react(workout, viewer, kind: "energy")

      summary = described_class.new(targets: [ workout ], viewer:).call.fetch(workout)

      expect(summary.mine).to eq("energy")
      expect(summary.reactors("energy")).to eq([ viewer ])
    end

    it "keeps a deleted or blocked account out of the names but counts its reaction" do
      deleted = local_actor("Parti")
      deleted.update!(tombstoned_at: Time.current)
      blocked = create(:actor, display_name: "Banni", uri: "https://blocked.example/users/demo")
      create(:federation_actor_block, actor_uri: "https://blocked.example/users/demo")
      react(workout, deleted, at: 2.hours.ago)
      react(workout, blocked, at: 1.hour.ago)
      react(workout, local_actor("Éric"), at: 30.minutes.ago)

      summary = described_class.new(targets: [ workout ], viewer: owner_actor).call.fetch(workout)

      expect(summary.count("beer")).to eq(3)
      expect(summary.reactors("beer").map(&:display_name)).to eq(%w[Éric])
    end

    it "keeps a deactivated account out of the names but counts its reaction" do
      suspended = local_actor("Suspendu")
      suspended.user.update!(suspended_at: Time.current)
      react(workout, suspended)

      summary = described_class.new(targets: [ workout ], viewer: owner_actor).call.fetch(workout)

      expect(summary.count("beer")).to eq(1)
      expect(summary.reactors("beer")).to be_empty
    end

    # docs/dev/REACTIONS.md: counts are global, names follow the audience.
    context "with a reaction given through the followers version" do
      let(:follower) { local_actor("Paul") }
      let(:stranger) { local_actor("Léa") }

      before do
        allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(true)
        create(:workout_publication, workout:, publishing_profile: public_publishing_profile_for(workout.user))
        create(:workout_publication, workout:,
                                     publishing_profile: workout.user.publishing_profiles.find_by!(built_in_key: "followers"))
        create(:following, :accepted, follower_actor: follower, followed_actor: owner_actor)
        react(workout, follower, at: 2.hours.ago).update_column(:audience, "followers")
        react(workout, local_actor("Éric"), at: 1.hour.ago)
      end

      it "counts it for a public reader without naming its author" do
        summary = described_class.new(targets: [ workout ], viewer: stranger).call.fetch(workout)

        expect(summary.count("beer")).to eq(2)
        expect(summary.reactors("beer").map(&:display_name)).to eq(%w[Éric])
      end

      it "names it to a follower, to its author and to the owner" do
        [ follower, owner_actor ].each do |viewer|
          summary = described_class.new(targets: [ workout ], viewer:).call.fetch(workout)
          expect(summary.reactors("beer").map(&:display_name)).to eq(%w[Éric Paul])
        end
      end
    end

    it "ignores a withdrawn reaction" do
      reaction = react(workout, local_actor("Éric"))
      reaction.undo!

      summary = described_class.new(targets: [ workout ], viewer: owner_actor).call.fetch(workout)

      expect(summary.count("beer")).to eq(0)
      expect(summary.reactors("beer")).to be_empty
    end

    it "summarises a received note apart from a workout" do
      note = create(:remote_note)
      react(note, local_actor("Éric"), kind: "coffee")

      summaries = described_class.new(targets: [ workout, note ], viewer: owner_actor).call

      expect(summaries.fetch(note).count("coffee")).to eq(1)
      expect(summaries.fetch(note).reactors("coffee").map(&:display_name)).to eq(%w[Éric])
      expect(summaries.fetch(workout).count("coffee")).to eq(0)
      expect(summaries.fetch(workout).reactors("coffee")).to be_empty
    end
  end
end
