# frozen_string_literal: true

require "rails_helper"

# docs/dev/AI.md §6: the scheduling seam. The facts are built here and cached on
# the row; the job re-reads them before it calls the model.
RSpec.describe Workouts::SummaryRefresh, :assistant do
  include ActiveJob::TestHelper

  let(:user) { create(:user, ai_enabled: true) }

  def workout(started_at: 2.days.ago)
    create(:workout, user:, started_at:)
  end

  it "writes nothing for a workout outside the automatic window" do
    described_class.schedule(workout(started_at: 40.days.ago))

    expect(WorkoutSummary.count).to eq(0)
    expect(Workouts::GenerateSummaryJob).not_to have_been_enqueued
  end

  it "marks the row pending with the facts and enqueues the generation" do
    record = workout

    described_class.schedule(record)

    row = record.reload.assistant_summary
    expect(row).to be_pending
    expect(row.locale).to eq("fr")
    expect(row.version).to eq(Allure::Insights::VERSION)
    expect(row.facts).not_to be_empty
    expect(row.facts.first).to include("id", "display")
    expect(row.facts_digest).to match(/\A\h{64}\z/)
    expect(Workouts::GenerateSummaryJob).to have_been_enqueued.with(record)
  end

  it "does nothing while the row is already pending" do
    record = workout
    described_class.schedule(record)
    clear_enqueued_jobs

    expect { described_class.schedule(record) }.not_to change { record.reload.assistant_summary.updated_at }
    expect(Workouts::GenerateSummaryJob).not_to have_been_enqueued
  end

  it "leaves a ready row alone while its facts and version match" do
    record = workout
    described_class.schedule(record)
    row = record.reload.assistant_summary
    snapshot = Workouts::SummaryFacts.new(record).call
    row.update!(status: "ready", facts_digest: snapshot.digest, version: Allure::Insights::VERSION)
    clear_enqueued_jobs

    described_class.schedule(record)

    expect(row.reload).to be_ready
    expect(Workouts::GenerateSummaryJob).not_to have_been_enqueued
  end

  it "regenerates a ready row whose facts moved" do
    record = workout
    described_class.schedule(record)
    row = record.reload.assistant_summary
    row.update!(status: "ready", facts_digest: "0" * 64, version: Allure::Insights::VERSION)
    clear_enqueued_jobs

    described_class.schedule(record)

    expect(row.reload).to be_pending
    expect(Workouts::GenerateSummaryJob).to have_been_enqueued
  end

  it "writes nothing without the owner's consent" do
    user.update!(ai_enabled: false)

    described_class.schedule(workout)

    expect(WorkoutSummary.count).to eq(0)
  end

  describe "the daily budget" do
    it "is spent by the calls of the rows touched in the last 24 hours" do
      ENV["AI_MAX_REQUESTS_PER_DAY"] = "1"
      create(:workout_summary, workout: create(:workout), requests_count: 1)

      expect(described_class).to be_budget_exhausted
    end

    it "ignores rows touched more than a day ago" do
      ENV["AI_MAX_REQUESTS_PER_DAY"] = "1"
      row = create(:workout_summary, workout: create(:workout), requests_count: 5)
      row.update_columns(updated_at: 2.days.ago)

      expect(described_class).not_to be_budget_exhausted
    end
  end
end
