# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workouts::BackfillRebuildJob do
  include ActiveJob::TestHelper

  def with_original_file(workout)
    workout.original_file.attach(
      io: StringIO.new("bytes"), filename: "ride.fit", content_type: "application/octet-stream"
    )
    workout
  end

  it "enqueues the rebuild for workouts stale in either generation" do
    facts = with_original_file(create(:workout, import_detection_version: 0))
    analysis = with_original_file(create(:workout, analysis_version: 1))
    with_original_file(create(:workout))
    # A stale but fileless workout has nothing to reconcile and is never
    # counted, so it cannot keep the sweep pending forever.
    create(:workout, import_detection_version: 0)

    expect { described_class.perform_now }
      .to have_enqueued_job(Workouts::RebuildJob).with(facts)
      .and have_enqueued_job(Workouts::RebuildJob).with(analysis)
    expect(Workouts::RebuildJob).to have_been_enqueued.exactly(:twice)
  end

  it "resumes from the cursor when a batch fills" do
    stub_const("Workouts::BackfillRebuildJob::BATCH_SIZE", 1)
    first = with_original_file(create(:workout, import_detection_version: 0))
    with_original_file(create(:workout, import_detection_version: 0))

    expect { described_class.perform_now(after_id: 0) }
      .to have_enqueued_job(described_class).with(after_id: first.id)
  end
end
