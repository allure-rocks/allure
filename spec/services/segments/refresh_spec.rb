# frozen_string_literal: true

require "rails_helper"

RSpec.describe Segments::Refresh do
  include ActiveJob::TestHelper

  let(:owner) { create(:user) }
  let(:rider) { create(:user) }
  let(:sport) { create(:sport) }
  let(:segment) { create(:segment, user: owner, sport:, visibility: "public", efforts_count: 9, athletes_count: 9) }

  def effort(user:, elapsed_time:, started_at: Time.zone.parse("2026-08-23 06:00:00"))
    workout = create(:workout, user:, sport:, started_at:)
    create(:segment_effort, workout:, segment:, elapsed_time:, started_at:)
  end

  it "recomputes the counters and one personal best per athlete and sport" do
    slow = effort(user: owner, elapsed_time: 90)
    fast = effort(user: owner, elapsed_time: 60, started_at: Time.zone.parse("2026-08-24 06:00:00"))
    other = effort(user: rider, elapsed_time: 120)

    described_class.call(segment)

    expect(segment.reload.efforts_count).to eq(3)
    expect(segment.athletes_count).to eq(2)
    expect(fast.reload.personal_best).to be(true)
    expect(slow.reload.personal_best).to be(false)
    expect(other.reload.personal_best).to be(true)
  end

  it "locks the segment row before rewriting its efforts" do
    effort(user: owner, elapsed_time: 90)
    statements = []
    subscriber = lambda do |_name, _start, _finish, _id, payload|
      statements << payload[:sql] if payload[:sql].match?(/FOR NO KEY UPDATE|UPDATE "segment_efforts"/)
    end

    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      described_class.call(segment)
    end

    expect(statements.first).to match(/FROM "segments".*FOR NO KEY UPDATE/)
    expect(statements.last).to match(/UPDATE "segment_efforts"/)
  end

  it "skips a segment deleted in the meantime" do
    Segment.where(id: segment.id).delete_all

    expect { described_class.call(segment) }.not_to raise_error
  end

  describe "after a workout deletion" do
    it "refreshes the segments the deleted workout had efforts on" do
      kept = effort(user: owner, elapsed_time: 90)
      best = effort(user: owner, elapsed_time: 60, started_at: Time.zone.parse("2026-08-24 06:00:00"))
      effort(user: rider, elapsed_time: 120)
      described_class.call(segment)
      expect(best.reload.personal_best).to be(true)

      perform_enqueued_jobs(only: Segments::RefreshJob) do
        Workouts::WorkoutDeletion.new(user: owner, workout: best.workout).call!
      end

      expect(segment.reload.efforts_count).to eq(2)
      expect(segment.athletes_count).to eq(2)
      expect(kept.reload.personal_best).to be(true)
    end

    it "drops an athlete whose only effort was deleted" do
      effort(user: owner, elapsed_time: 90)
      gone = effort(user: rider, elapsed_time: 120)
      described_class.call(segment)

      perform_enqueued_jobs(only: Segments::RefreshJob) do
        Workouts::WorkoutDeletion.new(user: rider, workout: gone.workout).call!
      end

      expect(segment.reload.efforts_count).to eq(1)
      expect(segment.athletes_count).to eq(1)
    end

    it "enqueues nothing for a workout without efforts" do
      workout = create(:workout, user: owner, sport:)

      expect {
        Workouts::WorkoutDeletion.new(user: owner, workout:).call!
      }.not_to have_enqueued_job(Segments::RefreshJob)
    end
  end
end
