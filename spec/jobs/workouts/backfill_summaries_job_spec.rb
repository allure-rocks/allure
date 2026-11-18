# frozen_string_literal: true

require "rails_helper"

# docs/dev/AI.md §6: the operator sweep only schedules the last 30 days, and
# only the rows that are missing, failed or built by an older generation.
RSpec.describe Workouts::BackfillSummariesJob, :assistant do
  include ActiveJob::TestHelper

  let(:user) { create(:user, ai_enabled: true) }

  def workout(started_at: 2.days.ago, owner: user)
    create(:workout, user: owner, started_at:)
  end

  it "covers a missing row, a failed one and an outdated one, never a current one" do
    missing = workout
    failed = workout
    create(:workout_summary, :failed, workout: failed)
    outdated = workout
    create(:workout_summary, workout: outdated, version: 0)
    current = workout
    create(:workout_summary, :ready, workout: current)
    workout(owner: create(:user))
    workout(started_at: 40.days.ago)

    expect(described_class.pending_scope).to contain_exactly(missing, failed, outdated)
  end

  it "schedules each pending workout and leaves the current row alone" do
    missing = workout
    current = workout
    create(:workout_summary, :ready, workout: current)

    described_class.perform_now

    expect(missing.reload.assistant_summary).to be_pending
    expect(current.reload.assistant_summary).to be_ready
    expect(Workouts::GenerateSummaryJob).to have_been_enqueued.with(missing).once
    expect(Workouts::GenerateSummaryJob).not_to have_been_enqueued.with(current)
  end

  it "is empty while the instance offers no assistant" do
    workout

    without_assistant { expect(described_class.pending_scope).to be_empty }
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
