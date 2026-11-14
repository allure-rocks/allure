# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workouts::BackfillElevationJob do
  let(:sport) { catalog_sport("running") }

  before { allow(Allure::Elevation::Config).to receive(:configured?).and_return(true) }

  def elevation_less_workout(opted_in: true)
    user = create(:user, elevation_enrichment_enabled: opted_in)
    create(:workout, user:, sport:, min_elevation: nil, max_elevation: nil)
  end

  it "enqueues the apply job for every pending workout" do
    pending = elevation_less_workout
    create(:workout, user: pending.user, sport:, min_elevation: 100.0)
    create(:workout, user: create(:user), sport:, min_elevation: nil, max_elevation: nil)
    create(:workout_elevation, workout: elevation_less_workout, status: "ready")

    expect(Workouts::ApplyElevationSourceJob).to receive(:perform_later).once.with(pending, "dem")

    described_class.perform_now(after_id: 0)
  end

  it "resumes from the cursor when a batch fills" do
    stub_const("Workouts::BackfillElevationJob::BATCH_SIZE", 1)
    first = elevation_less_workout
    elevation_less_workout

    expect(Workouts::ApplyElevationSourceJob).to receive(:perform_later).with(first, "dem").ordered
    expect(described_class).to receive(:perform_later).with(after_id: first.id).ordered

    described_class.perform_now(after_id: 0)
  end

  it "does nothing without a configured provider" do
    elevation_less_workout
    allow(Allure::Elevation::Config).to receive(:configured?).and_return(false)

    expect(Workouts::ApplyElevationSourceJob).not_to receive(:perform_later)

    described_class.perform_now(after_id: 0)
  end
end
