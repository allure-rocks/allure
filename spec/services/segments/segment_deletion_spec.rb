# frozen_string_literal: true

require "rails_helper"

RSpec.describe Segments::SegmentDeletion do
  let(:owner) { create(:user) }
  let(:segment) { create(:segment, user: owner) }

  before do
    allow(Segments::BackfillSegmentJob).to receive(:perform_later)
  end

  # A match writing efforts on the segment holds `FOR KEY SHARE` on its row
  # first; locking the row before destroying the efforts makes the two wait on
  # each other's commit instead of deadlocking over the efforts.
  it "locks the segment row before destroying its efforts" do
    workout = create(:workout, user: owner, sport: segment.sport)
    create(:segment_effort, workout:, segment:)
    statements = []
    subscriber = lambda do |_name, _start, _finish, _id, payload|
      statements << payload[:sql] if payload[:sql].match?(/FOR UPDATE|DELETE FROM "segment_efforts"/)
    end

    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      described_class.new(user: owner, segment:).call!
    end

    expect(statements.first).to match(/FROM "segments".*FOR UPDATE/)
    expect(statements).to include(a_string_matching(/DELETE FROM "segment_efforts"/))
    expect(Segment.exists?(segment.id)).to be(false)
    expect(SegmentEffort.where(workout:)).to be_empty
  end

  it "refuses another account's segment" do
    expect {
      described_class.new(user: create(:user), segment:).call!
    }.to raise_error(ActiveRecord::RecordNotFound)
    expect(Segment.exists?(segment.id)).to be(true)
  end
end
