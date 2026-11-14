# frozen_string_literal: true

require "rails_helper"

RSpec.describe Participations::Propose do
  let(:owner) { create(:user, username: "marie") }
  let(:participant) { create(:user, username: "paul") }
  let(:owner_actor) { create(:actor, :local, user: owner) }
  let(:participant_actor) { create(:actor, :local, user: participant) }
  let(:workout) { create(:workout, user: owner) }

  def propose(target: "paul", user: owner, source: workout)
    described_class.new(user:, workout: source, target:).call!
  end

  context "with an accepted follow" do
    before do
      owner_actor
      participant_actor
      create(:following, :accepted, follower_actor: participant_actor, followed_actor: owner_actor)
    end

    it "creates a credit confirmed by the owner and notifies the participant" do
      expect {
        propose
      }.to change(WorkoutParticipation, :count).by(1)

      participation = WorkoutParticipation.last
      expect(participation.kind).to eq("credit")
      expect(participation.origin).to eq("invitation")
      expect(participation.owner_confirmed_at).to be_present
      expect(participation.participant_confirmed_at).to be_nil
      expect(participation.participant_actor).to eq(participant_actor)

      notification = Notification.find_by(user: participant, kind: "participation_requested")
      expect(notification.subject).to eq(participation)
      expect(notification.actor).to eq(owner_actor)
    end

    it "accepts a local handle and is idempotent for a live pair" do
      propose(target: "@paul@#{Allure::Federation.config.domain}")

      expect {
        propose(target: "paul")
      }.not_to change(WorkoutParticipation, :count)
      expect(Notification.where(user: participant, kind: "participation_requested").count).to eq(1)
    end

    it "refuses the owner as their own participant" do
      expect { propose(target: "marie") }.to raise_error(described_class::NotAllowed)
    end

    it "keeps a declined pair terminal" do
      propose
      WorkoutParticipation.last.update!(declined_at: Time.current)

      expect { propose }.to raise_error(described_class::NotAllowed, /refusal/)
      expect(WorkoutParticipation.count).to eq(1)
    end

    it "allows a fresh invitation after a withdrawal" do
      propose
      WorkoutParticipation.last.update!(withdrawn_at: Time.current)

      expect { propose }.to change(WorkoutParticipation, :count).by(1)
    end

    it "never lets a withdrawn row shadow a live one on a repeated invitation" do
      propose
      WorkoutParticipation.last.update!(withdrawn_at: Time.current)
      propose

      expect { propose }.not_to change(WorkoutParticipation, :count)
      expect(WorkoutParticipation.live.count).to eq(1)
    end
  end

  it "refuses an account outside the follow gate" do
    owner_actor
    participant_actor

    expect { propose }.to raise_error(described_class::NotAllowed, /follow/)
    expect(WorkoutParticipation.count).to eq(0)
  end

  it "refuses an unknown account" do
    expect { propose(target: "nobody") }.to raise_error(described_class::NotAllowed)
  end

  # Remote invitations are covered end to end by
  # spec/federation/participation_invite_delivery_spec.rb (PLAN_TOGETHER.md §7).
  # The refusal reason depends on the environment's federation settings
  # (an unresolvable host here, a non-HTTPS URI in CI): any refusal will do.
  it "refuses a remote handle that cannot be resolved instead of failing" do
    expect { propose(target: "@paul@remote.example") }
      .to raise_error(described_class::NotAllowed)
  end

  it "refuses a non-owner" do
    owner_actor
    participant_actor
    create(:following, :accepted, follower_actor: participant_actor, followed_actor: owner_actor)

    expect { propose(user: participant) }.to raise_error(described_class::NotAllowed, /owner/)
  end
end
