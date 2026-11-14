# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workouts::BackfillToponymyJob do
  include ActiveJob::TestHelper

  before { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }

  it "schedules missing and outdated toponymies, and discards a virtual one" do
    missing = create(:workout)
    outdated = create(:workout_toponymy, algorithm_version: Workouts::ToponymyEnricher::ALGORITHM_VERSION - 1)
    create(:workout_toponymy)
    create(:workout, elevation_source_requested: "dem")
    virtual = create(:workout, sport: catalog_sport("rowing_virtual"))
    create(:workout_toponymy, workout: virtual)
    create(:workout, sport: catalog_sport("cycling_virtual"))

    expect(described_class.pending_scope).to contain_exactly(missing, outdated.workout, virtual)

    expect { described_class.perform_now(after_id: 0) }
      .to have_enqueued_job(Workouts::EnrichToponymyJob).with(missing)
      .and have_enqueued_job(Workouts::EnrichToponymyJob).with(outdated.workout)
    expect(Workouts::EnrichToponymyJob).to have_been_enqueued.exactly(:twice)
    expect(outdated.reload).to be_pending
    expect(virtual.reload.toponymy).to be_nil
  end

  it "resumes from the cursor when a batch fills" do
    stub_const("Workouts::BackfillToponymyJob::BATCH_SIZE", 1)
    first = create(:workout)
    create(:workout)

    expect { described_class.perform_now(after_id: 0) }
      .to have_enqueued_job(described_class).with(after_id: first.id)
  end
end
