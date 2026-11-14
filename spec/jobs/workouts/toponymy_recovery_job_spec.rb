# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workouts::ToponymyRecoveryJob do
  include ActiveJob::TestHelper

  before { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }

  it "reschedules a recent failure and a stuck pending toponymy" do
    failed = create(:workout_toponymy, status: "failed", updated_at: 7.hours.ago)
    stuck = create(:workout_toponymy, status: "pending", updated_at: 3.hours.ago)
    create(:workout_toponymy, status: "failed", updated_at: 1.hour.ago)
    create(:workout_toponymy, status: "failed", created_at: 3.days.ago, updated_at: 3.days.ago)
    create(:workout_toponymy, status: "pending", updated_at: 1.hour.ago)
    create(:workout_toponymy, status: "ready", updated_at: 3.days.ago)
    waiting = create(:workout, elevation_source_requested: "dem")
    create(:workout_toponymy, workout: waiting, status: "pending", updated_at: 3.hours.ago)

    expect(described_class.pending_scope).to contain_exactly(failed.workout, stuck.workout)

    allow(Allure::Toponyms::Config).to receive(:configured?).and_return(true)

    expect { described_class.perform_now }
      .to have_enqueued_job(Workouts::EnrichToponymyJob).exactly(:twice)
    expect(failed.reload).to be_pending
  end

  it "does nothing without a geocoding provider" do
    create(:workout_toponymy, status: "failed", updated_at: 7.hours.ago)

    allow(Allure::Toponyms::Config).to receive(:configured?).and_return(false)

    expect { described_class.perform_now }.not_to have_enqueued_job(Workouts::EnrichToponymyJob)
  end
end
