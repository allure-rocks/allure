# frozen_string_literal: true

require "rails_helper"

RSpec.describe Together::BackfillDetectionJob do
  include ActiveJob::TestHelper

  let(:version) { Allure::Together::Detector::VERSION }

  it "detects every recording the current detector has not seen, and a rerun finds nothing" do
    pending_one = create(:workout)
    seen = create(:workout, together_detection_version: version)
    create(:workout, :credit, credited_from: seen)

    expect(described_class.pending_scope).to contain_exactly(pending_one)

    perform_enqueued_jobs(only: [ described_class, Together::DetectWorkoutJob ]) { described_class.perform_later }

    expect(pending_one.reload.together_detection_version).to eq(version)
    expect(described_class.pending_scope).to be_empty
  end

  it "suggests an old outing once, whichever recording of the pair runs first" do
    marie = create(:user)
    paul = create(:user)
    marie_actor = create(:local_actor, user: marie)
    paul_actor = create(:local_actor, user: paul)
    create(:following, :accepted, follower_actor: marie_actor, followed_actor: paul_actor)
    create(:following, :accepted, follower_actor: paul_actor, followed_actor: marie_actor)
    sport = catalog_sport("cycling")
    [ marie, paul ].each { |user| create(:track_segment, workout: create(:workout, user:, sport:)) }

    perform_enqueued_jobs(only: [ described_class, Together::DetectWorkoutJob ]) { described_class.perform_later }

    expect(WorkoutParticipation.where(origin: "detection").count).to eq(1)
    expect(Notification.where(kind: "participation_suggested").count).to eq(2)
  end
end
