# frozen_string_literal: true

require "rails_helper"

RSpec.describe Segments::BackfillSegmentJob do
  before do
    allow(Segments::BackfillSegmentJob).to receive(:perform_later)
    allow(Segments::MatchWorkoutJob).to receive(:perform_later)
  end

  it "enqueues matching for candidate workouts" do
    workout = create(:workout)
    create(:track_segment, workout:)
    segment = create(:segment, user: workout.user, sport: workout.sport)

    described_class.perform_now(segment)

    expect(Segments::MatchWorkoutJob).to have_received(:perform_later).with(workout)
  end

  it "backfills the history of a route" do
    workout = create(:workout)
    create(:track_segment, workout:)
    route = create(:segment, :route, user: workout.user, sport: workout.sport)

    described_class.perform_now(route)

    expect(Segments::MatchWorkoutJob).to have_received(:perform_later).with(workout)
  end

  it "continues with the last cursor when a batch is full" do
    stub_const("Segments::BackfillSegmentJob::BATCH_SIZE", 1)
    first_workout = create(:workout)
    create(:track_segment, workout: first_workout)
    second_workout = create(:workout, user: first_workout.user, sport: first_workout.sport)
    create(:track_segment, workout: second_workout)
    segment = create(:segment, user: first_workout.user, sport: first_workout.sport)

    described_class.perform_now(segment)

    expect(Segments::BackfillSegmentJob).to have_received(:perform_later).with(segment, after_id: first_workout.id)
  end
end
