# frozen_string_literal: true

require "rails_helper"

RSpec.describe Segments::Standings do
  let(:viewer) { create(:user) }
  let(:other) { create(:user) }
  let(:owner) { create(:user) }
  let(:sport) { create(:sport) }

  def make_segment(visibility: "public", user: owner, segment_sport: sport)
    create(:segment, user:, sport: segment_sport, visibility:)
  end

  def make_effort(segment, user:, elapsed:, eligible: true, effort_sport: nil, average_speed: 5.0, average_pace: 200)
    workout = create(:workout, user:, sport: effort_sport || segment.sport || sport)
    if eligible
      create(:workout_publication, workout:, publishing_profile: public_publishing_profile_for(user), status: "active")
    end
    create(
      :segment_effort,
      segment:,
      workout:,
      user:,
      sport: workout.sport,
      elapsed_time: elapsed,
      moving_time: elapsed - 5,
      average_speed:,
      average_pace:
    )
  end

  it "ranks the viewer among the eligible best efforts" do
    segment = make_segment
    make_effort(segment, user: viewer, elapsed: 120)
    make_effort(segment, user: other, elapsed: 100)

    rows = described_class.new(segments: [ segment ], viewer:).call

    expect(rows.length).to eq(1)
    row = rows.first
    expect(row.segment).to eq(segment)
    expect(row.sport).to eq(sport)
    expect(row.rank).to eq(2)
    expect(row.participants).to eq(2)
    expect(row.elapsed_time).to eq(120)
    expect(row.average_pace).to eq(200)
    expect(row.average_speed).to eq(5.0)
    expect(row.ranked).to be(true)
  end

  it "keeps only each athlete's best eligible effort in the ranking" do
    segment = make_segment
    make_effort(segment, user: viewer, elapsed: 120)
    make_effort(segment, user: viewer, elapsed: 130, average_speed: 3.0, average_pace: 333)
    make_effort(segment, user: other, elapsed: 100)

    row = described_class.new(segments: [ segment ], viewer:).call.first

    expect(row.participants).to eq(2)
    expect(row.rank).to eq(2)
    expect(row.average_speed).to eq(5.0)
    expect(row.average_pace).to eq(200)
  end

  it "marks the viewer unranked when their effort is not eligible" do
    segment = make_segment
    make_effort(segment, user: viewer, elapsed: 120, eligible: false, average_speed: 4.0, average_pace: 250)
    make_effort(segment, user: other, elapsed: 100)

    row = described_class.new(segments: [ segment ], viewer:).call.first

    expect(row.ranked).to be(false)
    expect(row.rank).to be_nil
    expect(row.participants).to eq(1)
    expect(row.elapsed_time).to eq(120)
    expect(row.average_speed).to eq(4.0)
    expect(row.average_pace).to eq(250)
  end

  it "ignores other athletes' ineligible efforts" do
    segment = make_segment
    make_effort(segment, user: viewer, elapsed: 120)
    make_effort(segment, user: other, elapsed: 100, eligible: false)

    row = described_class.new(segments: [ segment ], viewer:).call.first

    expect(row.rank).to eq(1)
    expect(row.participants).to eq(1)
  end

  it "ignores an athlete who opted out of the segment" do
    segment = make_segment
    make_effort(segment, user: viewer, elapsed: 120)
    make_effort(segment, user: other, elapsed: 100)
    create(:segment_opt_out, segment:, user: other)

    row = described_class.new(segments: [ segment ], viewer:).call.first

    expect(row.rank).to eq(1)
    expect(row.participants).to eq(1)
  end

  it "keeps one row per sport on an all-sports segment" do
    segment = make_segment(segment_sport: nil)
    cycling = create(:sport)
    running = create(:sport)
    make_effort(segment, user: viewer, elapsed: 100, effort_sport: cycling)
    make_effort(segment, user: viewer, elapsed: 200, effort_sport: running)

    rows = described_class.new(segments: [ segment ], viewer:).call

    expect(rows.map(&:sport)).to contain_exactly(cycling, running)
  end

  it "returns nothing without a viewer or segments" do
    expect(described_class.new(segments: [], viewer:).call).to eq([])
    expect(described_class.new(segments: [ make_segment ], viewer: nil).call).to eq([])
  end
end
