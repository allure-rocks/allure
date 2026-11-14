# frozen_string_literal: true

require "rails_helper"

RSpec.describe Participations::Withdraw do
  let(:owner) { create(:user) }
  let(:participant) { create(:user) }
  let(:participant_actor) { create(:actor, :local, user: participant) }
  let(:workout) { create(:workout, user: owner) }
  let(:participation) { create(:workout_participation, workout:, participant_actor:) }

  def withdraw(user:)
    described_class.new(participation:, user:).call!
  end

  before do
    Notifications::Create.new(
      user: owner,
      kind: "participation_confirmed",
      actor: participant_actor,
      subject: participation
    ).call!
  end

  it "lets the owner withdraw and clears the notices" do
    withdraw(user: owner)

    expect(participation.reload).to be_withdrawn
    expect(participation).not_to be_active
    expect(Notification.where(subject: participation)).to be_empty
  end

  it "lets the participant withdraw" do
    withdraw(user: participant)

    expect(participation.reload).to be_withdrawn
  end

  it "refuses an unrelated account" do
    expect { withdraw(user: create(:user)) }
      .to raise_error(described_class::NotAllowed, /party/)
  end

  it "refuses a closed participation" do
    participation.update!(withdrawn_at: Time.current)

    expect { withdraw(user: owner) }
      .to raise_error(described_class::NotAllowed, /closed/)
  end
end
