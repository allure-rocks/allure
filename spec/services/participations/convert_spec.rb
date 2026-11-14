# frozen_string_literal: true

require "rails_helper"

RSpec.describe Participations::Convert do
  let(:owner) { create(:user) }
  let(:participant) { create(:user) }
  let(:participant_actor) { create(:actor, :local, user: participant) }
  let(:workout) { create(:workout, user: owner) }
  let(:recording) { create(:workout, user: participant) }
  let(:participation) { create(:workout_participation, workout:, participant_actor:) }

  def convert(user: participant, source: participation, participant_workout: recording)
    described_class.new(participation: source, user:, participant_workout:).call!
  end

  it "turns a confirmed credit into a link to the participant's recording" do
    convert

    participation.reload
    expect(participation.kind).to eq("link")
    expect(participation.participant_workout).to eq(recording)
    expect(participation).to be_confirmed
  end

  it "refuses a pending participation" do
    pending = create(:workout_participation, :pending, workout: create(:workout, user: owner), participant_actor:)

    expect { convert(source: pending) }.to raise_error(described_class::NotAllowed, /confirmed credit/)
  end

  it "refuses a participation that is already a link" do
    convert

    expect { convert(participant_workout: create(:workout, user: participant)) }
      .to raise_error(described_class::NotAllowed, /confirmed credit/)
  end

  it "refuses anyone but the participant" do
    expect { convert(user: owner) }.to raise_error(described_class::NotAllowed, /participant/)
  end

  it "refuses another account's workout" do
    expect { convert(participant_workout: create(:workout, user: owner)) }
      .to raise_error(described_class::NotAllowed, /participant's workout/)
  end

  it "refuses a recording already linked elsewhere" do
    create(:workout_participation, :link, workout: create(:workout, user: owner),
                                          participant_actor:, participant_workout: recording)

    expect { convert }.to raise_error(described_class::NotAllowed, /already linked/)
  end
end
