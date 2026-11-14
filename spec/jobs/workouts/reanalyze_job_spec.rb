# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workouts::ReanalyzeJob do
  it "delegates to the reanalysis service and re-matches the fresh geometry" do
    workout = create(:workout)
    reanalyzer = instance_double(Workouts::Reanalyzer, call!: workout)
    allow(Workouts::Reanalyzer).to receive(:new)
      .with(workout:, force: false, elevation_source: nil).and_return(reanalyzer)
    allow(Segments::MatchWorkoutJob).to receive(:perform_later)

    described_class.perform_now(workout)

    expect(reanalyzer).to have_received(:call!)
    expect(Segments::MatchWorkoutJob).to have_received(:perform_later).with(workout)
  end

  it "forces the requested elevation source" do
    workout = create(:workout)
    reanalyzer = instance_double(Workouts::Reanalyzer, call!: workout)
    allow(Workouts::Reanalyzer).to receive(:new)
      .with(workout:, force: true, elevation_source: "dem").and_return(reanalyzer)
    allow(Segments::MatchWorkoutJob).to receive(:perform_later)

    described_class.perform_now(workout, "dem")

    expect(reanalyzer).to have_received(:call!)
  end
end
