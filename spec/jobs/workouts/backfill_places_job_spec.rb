# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workouts::BackfillPlacesJob do
  include ActiveJob::TestHelper

  it "enqueues only usable toponymies with a stale list" do
    ready = create(:workout_toponymy)
    partial = create(:workout_toponymy, status: "partial")
    create(:workout_toponymy, status: "unavailable")
    create(:workout_toponymy, status: "failed")
    create(:workout_toponymy, algorithm_version: Workouts::ToponymyEnricher::ALGORITHM_VERSION - 1)
    create(:workout_toponymy, places_algorithm_version: Workouts::PlaceNamer::ALGORITHM_VERSION)

    expect { described_class.perform_now(after_id: 0) }
      .to have_enqueued_job(Workouts::RebuildPlacesJob).with(ready.workout)
      .and have_enqueued_job(Workouts::RebuildPlacesJob).with(partial.workout)
    expect(Workouts::RebuildPlacesJob).to have_been_enqueued.exactly(:twice)
  end

  it "resumes from the cursor when a batch fills" do
    stub_const("Workouts::BackfillPlacesJob::BATCH_SIZE", 1)
    first = create(:workout_toponymy)
    create(:workout_toponymy)

    expect { described_class.perform_now(after_id: 0) }
      .to have_enqueued_job(described_class).with(after_id: first.workout_id)
  end
end
