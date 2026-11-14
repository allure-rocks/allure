# frozen_string_literal: true

require "rails_helper"

# PLAN_TOGETHER.md §8: detection suggests a link between two co-present
# recordings of mutual followers who both opted in, once per pair.
RSpec.describe Together::Detection do
  let(:sport) { catalog_sport("cycling") }
  let(:marie) { create(:user, username: "marie") }
  let(:paul) { create(:user, username: "paul") }
  let!(:marie_actor) { create(:local_actor, user: marie) }
  let!(:paul_actor) { create(:local_actor, user: paul) }
  let!(:first) { recording(marie) }
  let!(:second) { recording(paul) }

  def recording(user, **attributes)
    workout = create(:workout, user:, sport:, **attributes)
    create(:track_segment, workout:)
    workout
  end

  def follow(follower, followed)
    create(:following, :accepted, follower_actor: follower, followed_actor: followed)
  end

  def mutual!
    follow(marie_actor, paul_actor)
    follow(paul_actor, marie_actor)
  end

  it "suggests a link between mutual followers' co-present recordings and tells both at once" do
    mutual!

    participations = described_class.call(second)

    participation = participations.sole
    expect(participation).to have_attributes(
      workout: first, participant_actor: paul_actor, participant_workout: second,
      kind: "link", origin: "detection", detector_version: Allure::Together::Detector::VERSION,
      owner_confirmed_at: nil, participant_confirmed_at: nil
    )
    expect(Notification.where(kind: "participation_suggested", subject: participation).pluck(:user_id))
      .to contain_exactly(marie.id, paul.id)
  end

  it "orients the pair the same way whichever recording is detected" do
    mutual!

    expect(described_class.call(first).sole.workout).to eq(first)
  end

  it "never suggests a pair twice, nor after a refusal" do
    mutual!
    participation = described_class.call(second).sole
    expect(described_class.call(first)).to be_empty

    participation.update!(declined_at: Time.current)
    expect(described_class.call(second)).to be_empty
  end

  it "leaves a pair with a credit between them to the credit-to-link suggestion" do
    mutual!
    create(:workout_participation, workout: first, participant_actor: paul_actor)

    expect(described_class.call(second)).to be_empty
  end

  it "compares only accounts that follow each other and both opted in" do
    follow(paul_actor, marie_actor)
    expect(described_class.call(second)).to be_empty

    follow(marie_actor, paul_actor)
    marie.update!(together_detection_enabled: false)
    expect(described_class.call(second)).to be_empty

    marie.update!(together_detection_enabled: true)
    expect(described_class.call(second).size).to eq(1)
  end

  it "skips commutes, another time, and credit rows" do
    mutual!
    first.update!(commute: true)
    expect(described_class.call(second)).to be_empty

    first.update!(commute: false, started_at: second.started_at + 3.hours)
    first.track_segments.update_all(started_at: first.started_at)
    expect(described_class.call(second)).to be_empty

    credit = create(:workout, :credit, user: paul, sport:, credited_from: first, credited_by: marie_actor)
    expect(described_class.call(credit)).to be_empty
  end
end
