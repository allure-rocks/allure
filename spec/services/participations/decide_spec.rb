# frozen_string_literal: true

require "rails_helper"

RSpec.describe Participations::Decide do
  let(:owner) { create(:user) }
  let(:participant) { create(:user) }
  let(:participant_actor) { create(:actor, :local, user: participant) }
  let(:workout) { create(:workout, user: owner, title: "Sortie du soir") }
  let(:participation) do
    create(:workout_participation, :pending, workout:, participant_actor:)
  end

  def decide(decision:, user: participant, source: participation, participant_workout: nil)
    described_class.new(participation: source, user:, decision:, participant_workout:).call!
  end

  it "confirms and notifies the owner" do
    expect {
      decide(decision: "confirm")
    }.to change { Notification.where(user: owner, kind: "participation_confirmed").count }.by(1)

    expect(participation.reload).to be_confirmed
    expect(Notification.find_by(user: owner, kind: "participation_confirmed").actor).to eq(participant_actor)
    expect(Notification.where(user: participant, kind: "participation_requested")).to be_empty
  end

  it "declines, closes the pair, and withdraws the request notice" do
    Notifications::Create.new(
      user: participant,
      kind: "participation_requested",
      actor: owner.actor,
      subject: participation
    ).call!

    decide(decision: "decline")

    expect(participation.reload).to be_declined
    expect(participation).not_to be_active
    expect(Notification.where(user: participant, kind: "participation_requested")).to be_empty
  end

  it "switches the credit to a link when the participant names their recording" do
    recording = create(:workout, user: participant)

    decide(decision: "confirm", participant_workout: recording)

    participation.reload
    expect(participation.kind).to eq("link")
    expect(participation.participant_workout).to eq(recording)
    expect(participation).to be_confirmed
  end

  it "refuses another account's recording" do
    recording = create(:workout, user: owner)

    expect {
      decide(decision: "confirm", participant_workout: recording)
    }.to raise_error(described_class::NotAllowed)
  end

  it "refuses a recording that is already linked to another source" do
    recording = create(:workout, user: participant)
    other_source = create(:workout, user: owner)
    create(:workout_participation, :link, workout: other_source,
                                          participant_actor:, participant_workout: recording)

    expect {
      decide(decision: "confirm", participant_workout: recording)
    }.to raise_error(described_class::NotAllowed, /already linked/)
  end

  it "refuses a non-participant, the owner of an invitation included" do
    expect { decide(decision: "confirm", user: owner) }
      .to raise_error(described_class::NotAllowed, /party/)
  end

  describe "a detection" do
    let(:owner_actor) { create(:actor, :local, user: owner) }
    let(:recording) { create(:workout, user: participant) }
    let(:participation) do
      owner_actor
      create(:workout_participation, workout:, participant_actor:, kind: "link", origin: "detection",
                                     participant_workout: recording, owner_confirmed_at: nil,
                                     participant_confirmed_at: nil)
    end

    it "needs both sides, and each confirmation tells the other" do
      decide(decision: "confirm", user: owner)
      expect(participation.reload).not_to be_confirmed
      expect(Notification.find_by(user: participant, kind: "participation_confirmed").actor).to eq(owner_actor)

      decide(decision: "confirm", user: participant)
      expect(participation.reload).to be_confirmed
      expect(Notification.find_by(user: owner, kind: "participation_confirmed").actor).to eq(participant_actor)
    end

    it "withdraws only the confirming side's suggestion notice" do
      [ [ owner, participant_actor ], [ participant, owner_actor ] ].each do |user, actor|
        Notifications::Create.new(user:, kind: "participation_suggested", actor:, subject: participation).call!
      end

      decide(decision: "confirm", user: owner)

      expect(Notification.where(kind: "participation_suggested").pluck(:user_id)).to eq([ participant.id ])
    end

    it "is refused for good by either side" do
      decide(decision: "decline", user: owner)

      expect(participation.reload).to be_declined
      expect { decide(decision: "confirm", user: participant) }.to raise_error(described_class::NotAllowed, /closed/)
    end

    it "refuses a side answering twice, and a stranger" do
      decide(decision: "confirm", user: owner)

      expect { decide(decision: "confirm", user: owner) }.to raise_error(described_class::NotAllowed, /already/)
      expect { decide(decision: "confirm", user: create(:user)) }.to raise_error(described_class::NotAllowed, /party/)
    end
  end

  it "refuses a closed participation" do
    participation.update!(withdrawn_at: Time.current)

    expect { decide(decision: "confirm") }
      .to raise_error(described_class::NotAllowed, /closed/)
  end

  it "refuses an unknown decision" do
    expect { decide(decision: "maybe") }.to raise_error(described_class::NotAllowed, /decision/)
  end
end
