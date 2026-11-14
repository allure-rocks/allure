# frozen_string_literal: true

require "rails_helper"

RSpec.describe WorkoutParticipation do
  let(:owner) { create(:user) }
  let(:participant) { create(:user) }
  let(:workout) { create(:workout, user: owner) }
  let(:participant_actor) { create(:actor, :local, user: participant) }

  describe "validations" do
    it "accepts a credit without a recording and a link with one" do
      expect(build(:workout_participation, workout:, participant_actor:)).to be_valid
      expect(build(:workout_participation, :link, workout:, participant_actor:)).to be_valid
    end

    it "rejects a link without a recording and a credit with one" do
      expect(build(:workout_participation, workout:, participant_actor:, kind: "link")).not_to be_valid

      recording = create(:workout, user: participant)
      expect(build(:workout_participation, workout:, participant_actor:, participant_workout: recording)).not_to be_valid
    end

    it "keeps a detection a link" do
      expect(build(:workout_participation, workout:, participant_actor:, origin: "detection")).not_to be_valid
      expect(build(:workout_participation, :link, workout:, participant_actor:, origin: "detection")).to be_valid
    end

    it "refuses the source owner as the participant" do
      owner_actor = create(:actor, :local, user: owner)

      expect(build(:workout_participation, workout:, participant_actor: owner_actor)).not_to be_valid
    end

    it "requires the recording to belong to the participant" do
      other_recording = create(:workout)

      expect(build(:workout_participation, :link, workout:, participant_actor:, participant_workout: other_recording))
        .not_to be_valid
    end

    it "accepts only known kinds and origins" do
      expect(build(:workout_participation, workout:, participant_actor:, kind: "tag")).not_to be_valid
      expect(build(:workout_participation, workout:, participant_actor:, origin: "guess")).not_to be_valid
    end
  end

  describe "confirmation" do
    it "derives confirmed? from both timestamps" do
      participation = build(:workout_participation, :pending, workout:, participant_actor:)
      expect(participation).not_to be_confirmed

      participation.participant_confirmed_at = Time.current
      expect(participation).to be_confirmed
    end

    it "keeps a declined row out of active but live" do
      participation = create(:workout_participation, :declined, workout:, participant_actor:)

      expect(described_class.active).not_to include(participation)
      expect(described_class.live).to include(participation)
      expect(participation).to be_declined
    end
  end

  describe "database boundaries" do
    it "allows one live row per pair and frees it only on withdrawal" do
      first = create(:workout_participation, workout:, participant_actor:)

      expect { create(:workout_participation, workout:, participant_actor:) }
        .to raise_error(ActiveRecord::RecordNotUnique, /index_workout_participations_live_pair/)

      first.update!(withdrawn_at: Time.current)
      expect(create(:workout_participation, workout:, participant_actor:)).to be_persisted
    end

    it "links one recording to one source" do
      recording = create(:workout, user: participant)
      create(:workout_participation, :link, workout:, participant_actor:, participant_workout: recording)
      other_source = create(:workout, user: owner)

      expect {
        create(:workout_participation, :link, workout: other_source, participant_actor:, participant_workout: recording)
      }.to raise_error(ActiveRecord::RecordNotUnique, /index_workout_participations_live_recording/)
    end

    it "rejects an unknown kind at the database boundary" do
      expect {
        described_class.insert_all!([ {
          workout_id: workout.id,
          participant_actor_id: participant_actor.id,
          kind: "tag",
          origin: "invitation",
          created_at: Time.current,
          updated_at: Time.current
        } ])
      }.to raise_error(ActiveRecord::StatementInvalid, /workout_participations_kind/)
    end
  end
end
