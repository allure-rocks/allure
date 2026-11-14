# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workouts::ToponymyRefresh do
  include ActiveJob::TestHelper

  before { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }

  it "creates a pending toponymy and schedules geocoding" do
    workout = create(:workout)

    expect { described_class.new(workout:).call }
      .to have_enqueued_job(Workouts::EnrichToponymyJob).with(workout)
    expect(workout.reload.toponymy).to have_attributes(
      status: "pending",
      algorithm_version: Workouts::ToponymyEnricher::ALGORITHM_VERSION
    )
  end

  it "marks a settled toponymy pending so the enricher does not skip it" do
    toponymy = create(:workout_toponymy, updated_at: 1.day.ago)

    expect { described_class.new(workout: toponymy.workout).call }
      .to have_enqueued_job(Workouts::EnrichToponymyJob).with(toponymy.workout)
    expect(toponymy.reload).to be_pending
    expect(toponymy.updated_at).to be > 1.minute.ago
  end

  it "discards a legacy toponymy on a virtual workout without geocoding" do
    workout = create(:workout, sport: catalog_sport("rowing_virtual"))
    create(:workout_toponymy, workout:)

    expect { described_class.new(workout:).call }
      .not_to have_enqueued_job(Workouts::EnrichToponymyJob)
    expect(workout.reload.toponymy).to be_nil
  end

  it "marks the toponymy failed when the job cannot be enqueued" do
    workout = create(:workout)
    allow(Workouts::EnrichToponymyJob).to receive(:perform_later).and_raise("queue unavailable")

    described_class.new(workout:).call

    expect(workout.reload.toponymy).to have_attributes(status: "failed", last_error: "queue unavailable")
  end
end
