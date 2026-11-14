# frozen_string_literal: true

require "rails_helper"

RSpec.describe Reaction do
  let!(:actor) { create(:actor) }

  describe "validations" do
    it "requires exactly one target" do
      workout = create(:workout)
      note = create(:remote_note)

      expect(build(:reaction, actor:, workout:)).to be_valid
      expect(build(:reaction, actor:, workout:, remote_note: note)).not_to be_valid
      expect(build(:reaction, actor:, workout: nil)).not_to be_valid
    end

    it "accepts only known kinds" do
      expect(build(:reaction, actor:, kind: "beer")).to be_valid
      expect(build(:reaction, actor:, kind: "wine")).not_to be_valid
    end

    it "requires an absolute activity URI" do
      expect(build(:reaction, actor:, uri: "not-a-uri")).not_to be_valid
      expect(build(:reaction, actor:, uri: "https://remote.example/activities/1")).to be_valid
    end

    it "enforces one active reaction per actor and target at the database boundary" do
      workout = create(:workout)
      note = create(:remote_note)
      create(:reaction, actor:, workout:)

      expect { create(:reaction, actor:, workout:) }
        .to raise_error(ActiveRecord::RecordNotUnique, /index_active_reactions_on_actor_and_workout/)

      create(:reaction, :remote_note, actor:, remote_note: note)
      expect { create(:reaction, :remote_note, actor:, remote_note: note) }
        .to raise_error(ActiveRecord::RecordNotUnique, /index_active_reactions_on_actor_and_remote_note/)
    end

    it "rejects a target-less row at the database boundary" do
      expect {
        described_class.insert_all!([ {
          actor_id: actor.id,
          uri: "https://remote.example/activities/orphan",
          kind: "like",
          audience: "public",
          created_at: Time.current,
          updated_at: Time.current
        } ])
      }.to raise_error(ActiveRecord::StatementInvalid, /reactions_single_target/)
    end

    it "rejects an unknown kind at the database boundary" do
      workout = create(:workout)

      expect {
        described_class.insert_all!([ {
          actor_id: actor.id,
          workout_id: workout.id,
          uri: "https://remote.example/activities/wine",
          kind: "wine",
          audience: "public",
          created_at: Time.current,
          updated_at: Time.current
        } ])
      }.to raise_error(ActiveRecord::StatementInvalid, /reactions_kind/)
    end

    it "rejects an unknown audience at the database boundary" do
      workout = create(:workout)

      expect {
        described_class.insert_all!([ {
          actor_id: actor.id,
          workout_id: workout.id,
          uri: "https://remote.example/activities/group",
          kind: "like",
          audience: "group",
          created_at: Time.current,
          updated_at: Time.current
        } ])
      }.to raise_error(ActiveRecord::StatementInvalid, /reactions_audience/)
    end
  end

  describe "#undo!" do
    it "allows an undone reaction to be recreated with a new identity" do
      workout = create(:workout)
      reaction = create(:reaction, actor:, workout:, kind: "beer")

      reaction.undo!
      expect(reaction.reload).not_to be_active

      expect {
        create(:reaction, actor:, workout:, kind: "coffee")
      }.to change(described_class, :count).by(1)
      expect(described_class.active.find_by(actor:, workout:).kind).to eq("coffee")
    end

    it "is idempotent and keeps the first withdrawal instant" do
      reaction = create(:reaction, actor:)
      first = Time.utc(2026, 9, 28, 10)

      reaction.undo!(at: first)
      reaction.undo!(at: first + 1.hour)

      expect(reaction.reload.undone_at).to eq(first)
    end
  end
end
