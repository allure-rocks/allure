# frozen_string_literal: true

require "rails_helper"

RSpec.describe Segments::Podiums do
  let(:viewer) { create(:user) }
  let(:other) { create(:user) }
  let(:owner) { create(:user) }
  let(:sport) { create(:sport) }

  def make_segment(visibility: "public", user: owner, segment_sport: sport)
    create(:segment, user:, sport: segment_sport, visibility:)
  end

  # The index rows: one per course and sport, as the list query yields them.
  def rows_for(*segments)
    Segments::ListQuery.new(viewer:, params: {}).resolve(Segment.where(id: segments.map(&:id))).to_a
  end

  def podiums(*segments) = described_class.new(rows: rows_for(*segments), viewer:).call

  def make_effort(segment, user:, elapsed:, eligible: true, effort_sport: nil)
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
      moving_time: elapsed - 5
    )
  end

  it "returns the top three of the board and marks the viewer's rank" do
    segment = make_segment
    make_effort(segment, user: other, elapsed: 100)
    make_effort(segment, user: create(:user), elapsed: 110)
    make_effort(segment, user: viewer, elapsed: 120)

    row = podiums(segment).fetch([ segment.id, segment.sport_id ])

    expect(row.sport).to eq(sport)
    expect(row.top.map(&:elapsed_time)).to eq([ 100, 110, 120 ])
    expect(row.participants).to eq(3)
    expect(row.viewer_rank).to eq(3)
    expect(row.viewer_ranked).to be(true)
    expect(row.viewer_effort.elapsed_time).to eq(120)
  end

  it "caps the podium at three and keeps only each athlete's best eligible effort" do
    segment = make_segment
    make_effort(segment, user: other, elapsed: 100)
    make_effort(segment, user: other, elapsed: 90)
    3.times { |index| make_effort(segment, user: create(:user), elapsed: 110 + index) }

    row = podiums(segment).fetch([ segment.id, segment.sport_id ])

    expect(row.top.length).to eq(3)
    expect(row.top.first.user).to eq(other)
    expect(row.top.first.elapsed_time).to eq(90)
    expect(row.participants).to eq(4)
    expect(row.viewer_effort).to be_nil
    expect(row.viewer_ranked).to be(false)
  end

  it "gives an all-sports course one row per sport, each with its own board and best" do
    segment = make_segment(segment_sport: nil)
    cycling = create(:sport)
    running = create(:sport)
    2.times { make_effort(segment, user: create(:user), elapsed: 100, effort_sport: cycling) }
    make_effort(segment, user: viewer, elapsed: 120, effort_sport: running)
    make_effort(segment, user: other, elapsed: 130, effort_sport: running)

    result = podiums(segment)

    expect(result.keys).to contain_exactly([ segment.id, cycling.id ], [ segment.id, running.id ])
    running_row = result.fetch([ segment.id, running.id ])
    expect(running_row.sport).to eq(running)
    expect(running_row.top.map(&:user)).to eq([ viewer, other ])
    expect(running_row.viewer_rank).to eq(1)
    cycling_row = result.fetch([ segment.id, cycling.id ])
    expect(cycling_row.participants).to eq(2)
    expect(cycling_row.viewer_effort).to be_nil
  end

  it "keeps one sportless row for an all-sports course nobody ran" do
    segment = make_segment(segment_sport: nil)

    row = podiums(segment).fetch([ segment.id, nil ])

    expect(row.sport).to be_nil
    expect(row.top).to be_empty
    expect(row.viewer_effort).to be_nil
  end

  it "shows no board for a private course but keeps the owner's personal record" do
    segment = make_segment(visibility: "private")
    make_effort(segment, user: viewer, elapsed: 120)

    row = podiums(segment).fetch([ segment.id, segment.sport_id ])

    expect(row.sport).to eq(sport)
    expect(row.top).to be_empty
    expect(row.participants).to eq(0)
    expect(row.viewer_effort.elapsed_time).to eq(120)
    expect(row.viewer_ranked).to be(false)
  end

  it "keeps an opted-out athlete off the board" do
    segment = make_segment
    make_effort(segment, user: other, elapsed: 100)
    make_effort(segment, user: viewer, elapsed: 120)
    create(:segment_opt_out, segment:, user: other)

    row = podiums(segment).fetch([ segment.id, segment.sport_id ])

    expect(row.top.map(&:user)).to eq([ viewer ])
    expect(row.participants).to eq(1)
    expect(row.viewer_rank).to eq(1)
  end

  it "keys every row by segment and sport and returns nothing without rows" do
    segment = make_segment

    expect(podiums(segment).keys).to eq([ [ segment.id, sport.id ] ])
    expect(described_class.new(rows: [], viewer:).call).to eq({})
  end
end
