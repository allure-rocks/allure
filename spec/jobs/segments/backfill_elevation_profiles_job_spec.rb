# frozen_string_literal: true

require "rails_helper"

RSpec.describe Segments::BackfillElevationProfilesJob do
  include ActiveJob::TestHelper

  it "enqueues a build for source-backed segments without a profile only" do
    missing = create(:segment, source_workout: create(:workout), elevation_profile: nil)
    create(:segment, source_workout: create(:workout), elevation_profile: [])
    create(:segment, elevation_profile: nil)
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    expect { described_class.perform_now }
      .to have_enqueued_job(Segments::BuildElevationProfileJob).with(missing)
    expect(Segments::BuildElevationProfileJob).to have_been_enqueued.exactly(:once)
  end

  it "resumes from the cursor when a batch fills" do
    stub_const("Segments::BackfillElevationProfilesJob::BATCH_SIZE", 1)
    first = create(:segment, source_workout: create(:workout))
    create(:segment, source_workout: create(:workout))
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    expect { described_class.perform_now(after_id: 0) }
      .to have_enqueued_job(described_class).with(after_id: first.id)
  end
end
