# frozen_string_literal: true

require "rails_helper"

# docs/dev/AI.md §6: the recurring recovery re-schedules recent failures and
# stuck pending rows, and nothing older than the automatic window.
RSpec.describe Workouts::SummaryRecoveryJob, :assistant do
  include ActiveJob::TestHelper

  let(:user) { create(:user, ai_enabled: true) }

  def workout(started_at: 2.days.ago)
    create(:workout, user:, started_at:)
  end

  def summary(record, status:, updated_at:, created_at: nil)
    create(:workout_summary, workout: record, status:).tap do |row|
      row.update_columns(updated_at:, created_at: created_at || updated_at)
    end
  end

  it "re-schedules a stuck pending row" do
    record = workout
    summary(record, status: "pending", updated_at: 3.hours.ago)

    expect(described_class.pending_scope).to include(record)
    expect { described_class.perform_now }.to have_enqueued_job(Workouts::GenerateSummaryJob).with(record)
  end

  it "re-schedules a recent failure" do
    record = workout
    summary(record, status: "failed", updated_at: 7.hours.ago, created_at: 1.day.ago)

    expect(described_class.pending_scope).to include(record)
  end

  it "leaves a fresh pending row alone" do
    record = workout
    summary(record, status: "pending", updated_at: 10.minutes.ago)

    expect(described_class.pending_scope).not_to include(record)
  end

  it "leaves a failure older than two days alone" do
    record = workout
    summary(record, status: "failed", updated_at: 7.hours.ago, created_at: 3.days.ago)

    expect(described_class.pending_scope).not_to include(record)
  end

  it "ignores a workout outside the automatic window" do
    record = workout(started_at: 40.days.ago)
    summary(record, status: "pending", updated_at: 3.hours.ago)

    expect(described_class.pending_scope).not_to include(record)
  end

  it "does nothing while the instance offers no assistant" do
    record = workout
    summary(record, status: "pending", updated_at: 3.hours.ago)

    without_assistant { described_class.perform_now }

    expect(Workouts::GenerateSummaryJob).not_to have_been_enqueued
  end

  def without_assistant
    keys = %w[AI_BASE_URL AI_MODEL]
    previous = keys.to_h { |key| [ key, ENV[key] ] }
    keys.each { |key| ENV.delete(key) }
    yield
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
