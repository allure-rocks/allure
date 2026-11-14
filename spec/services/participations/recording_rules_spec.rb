# frozen_string_literal: true

require "rails_helper"

RSpec.describe Participations::RecordingRules do
  let(:owner) { create(:user) }
  let(:participant) { create(:user) }
  let(:participant_actor) { create(:actor, :local, user: participant) }
  let(:source_start) { Time.zone.parse("2026-08-23 06:00:00") }
  let(:workout) { create(:workout, user: owner, started_at: source_start) }
  let(:participation) { create(:workout_participation, :pending, workout:, participant_actor:) }

  def recording(offset, user: participant)
    create(:workout, user:, started_at: source_start + offset)
  end

  describe ".candidates" do
    it "offers the participant's recordings within six hours, closest first" do
      far = recording(-5.hours)
      close = recording(10.minutes)
      middle = recording(2.hours)
      recording(7.hours)
      recording(1.minute, user: owner)

      expect(described_class.candidates(participation:, user: participant).to_a).to eq([ close, middle, far ])
    end

    it "leaves out a recording already linked to a live participation" do
      linked = recording(5.minutes)
      create(:workout_participation, :link, workout: create(:workout, user: owner),
                                            participant_actor:, participant_workout: linked)
      free = recording(20.minutes)

      expect(described_class.candidates(participation:, user: participant).to_a).to eq([ free ])
    end

    it "offers at most ten recordings" do
      11.times { |index| recording(index.minutes) }

      expect(described_class.candidates(participation:, user: participant).size).to eq(described_class::LIMIT)
    end
  end

  describe ".refusal" do
    it "accepts the participant's own free recording" do
      expect(described_class.refusal(participation:, user: participant, recording: recording(0))).to be_nil
    end

    # Unreachable through a real participant (the source is never theirs); the
    # rule still guards any future caller.
    it "refuses the source workout" do
      participation
      allow(workout).to receive(:user_id).and_return(participant.id)

      expect(described_class.refusal(participation:, user: participant, recording: workout)).to match(/source/)
    end
  end
end
