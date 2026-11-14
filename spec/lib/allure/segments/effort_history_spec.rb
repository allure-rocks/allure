# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Segments::EffortHistory do
  let(:effort_value) { Data.define(:id, :sport_id, :workout_id, :started_at, :elapsed_time) }
  let(:day) { Time.utc(2026, 3, 1, 8) }

  def effort(id, elapsed, days:, sport_id: 1, workout_id: id, minutes: 0)
    effort_value.new(id:, sport_id:, workout_id:, started_at: day + days.days + minutes.minutes, elapsed_time: elapsed)
  end

  it "orders entries oldest first with their personal place and gap to the record" do
    history = described_class.new([
      effort(3, 290, days: 10),
      effort(1, 300, days: 0),
      effort(2, 310, days: 5),
      effort(4, 280, days: 20)
    ])

    entries = history.series.sole.entries
    expect(entries.map { it.effort.id }).to eq([ 1, 2, 3, 4 ])
    expect(entries.map(&:place)).to eq([ 3, nil, 2, 1 ])
    expect(entries.map(&:gap_to_best)).to eq([ 20, 30, 10, 0 ])
  end

  it "places the earlier effort first on a tie" do
    entries = described_class.new([ effort(1, 300, days: 0), effort(2, 300, days: 1) ]).series.sole.entries

    expect(entries.map(&:place)).to eq([ 1, 2 ])
  end

  it "splits the history per sport, fastest sport first, with places per sport" do
    history = described_class.new([
      effort(1, 600, days: 0, sport_id: 7),
      effort(2, 300, days: 1, sport_id: 9),
      effort(3, 590, days: 2, sport_id: 7)
    ])

    expect(history.series.map(&:sport_id)).to eq([ 9, 7 ])
    expect(history.series.last.entries.map(&:place)).to eq([ 2, 1 ])
    expect(history.entries.map { it.effort.id }).to eq([ 1, 2, 3 ])
  end

  it "draws a robust straight trend while the outings are few" do
    times = [ 300, 295, 290, 400, 280, 275 ]
    history = described_class.new(times.each_with_index.map { |time, index| effort(index + 1, time, days: index * 7) })

    # The Theil–Sen line through the outings: the 400 does not tilt it.
    trend = history.series.sole.trend
    outings = trend.select { |point| history.series.sole.entries.map { it.effort.started_at }.include?(point.started_at) }
    expect(outings.map(&:elapsed_time)).to match([ 300, 295, 290, 285, 280, 275 ].map { be_within(1e-6).of(it) })
    expect(trend).to all(have_attributes(reliable: true))
  end

  it "evaluates the trend on a regular grid holding every outing, strictly increasing" do
    times = [ 300, 295, 290, 400, 280, 275 ]
    history = described_class.new(times.each_with_index.map { |time, index| effort(index + 1, time, days: index * 7) })

    trend = history.series.sole.trend
    # Weekly outings fall on the grid (every 20th step): 99 inner steps plus
    # the two ends.
    expect(trend.size).to eq(described_class::TREND_GRID + 1)
    expect(trend.map(&:started_at).each_cons(2)).to all(satisfy { |a, b| a < b })
    expect(trend.map(&:started_at)).to include(*history.series.sole.entries.map { it.effort.started_at })
  end

  it "dots the trend across a long gap and never jumps beside it" do
    # Three years of weekly-ish bursts, then a single outing two years on.
    efforts = (0...40).map { |index| effort(index + 1, 3600 + (index % 5) * 60 - index * 5, days: index * 25) }
    last_burst = efforts.last.started_at
    efforts << effort(99, 3700, days: 39 * 25 + 730)
    trend = described_class.new(efforts).series.sole.trend

    dotted = trend.reject(&:reliable)
    expect(dotted.first.started_at).to eq(last_burst)
    expect(trend.last(2).first).not_to be_reliable
    expect(trend.select { it.started_at < last_burst }).to all(be_reliable)
    steps = trend.each_cons(2).map { |a, b| (b.elapsed_time - a.elapsed_time).abs }
    expect(steps.max).to be < 30
  end

  it "keeps a seasonal break solid on a long history" do
    # A winter off (seven months) inside six years: under 15 % of the span.
    days = (0...30).map { it * 10 } + (0...150).map { 510 + it * 12 }
    trend = described_class.new(days.each_with_index.map { |day, index| effort(index + 1, 3600, days: day) }).series.sole.trend

    expect(trend).to all(be_reliable)
  end

  it "dots the whole trend under five outings" do
    history = described_class.new((0...4).map { |index| effort(index + 1, 300 - index, days: index * 7) })

    expect(history.series.sole.trend).to be_present.and(all(have_attributes(reliable: false)))
  end

  it "copes with outings sharing one start" do
    history = described_class.new((0...6).map { |index| effort(index + 1, 300 + index, days: index < 2 ? 0 : index) })

    expect(history.series.sole.trend.map(&:elapsed_time)).to all(be_finite)
  end

  it "draws a robust curve from eight outings, following the times at the ends" do
    times = [ 330, 325, 318, 312, 306, 300, 295, 291, 300, 288 ]
    history = described_class.new(times.each_with_index.map { |time, index| effort(index + 1, time, days: index * 7) })

    trend = history.series.sole.trend.map(&:elapsed_time)
    expect(trend.first).to be > 325
    expect(trend.last).to be < 292
  end

  it "counts the laps of one outing as their mean in the trend" do
    history = described_class.new([
      effort(1, 300, days: 0),
      effort(2, 400, days: 7, workout_id: 20),
      effort(3, 420, days: 7, workout_id: 20, minutes: 10),
      effort(4, 440, days: 7, workout_id: 20, minutes: 20),
      effort(5, 320, days: 14)
    ])

    # Outings 300, 420 (the mean of 400, 420, 440) and 320, one week apart:
    # their Theil–Sen line (slope 10 a week, the median of 120, 10 and −100).
    trend = history.series.sole.trend
    expect([ trend.first, trend[described_class::TREND_GRID / 2], trend.last ].map(&:elapsed_time))
      .to match([ 300, 310, 320 ].map { be_within(0.001).of(it) })
  end

  it "draws no trend under three outings" do
    history = described_class.new([
      effort(1, 300, days: 0, workout_id: 9),
      effort(2, 290, days: 0, workout_id: 9, minutes: 10),
      effort(3, 295, days: 3)
    ])

    expect(history.series.sole.trend).to be_empty
  end

  it "is chartable only from two efforts" do
    expect(described_class.new([])).not_to be_chartable
    expect(described_class.new([ effort(1, 300, days: 0) ])).not_to be_chartable
    expect(described_class.new([ effort(1, 300, days: 0), effort(2, 290, days: 1) ])).to be_chartable
  end

  it "charts each sport from its own two efforts" do
    history = described_class.new([
      effort(1, 600, days: 0, sport_id: 7),
      effort(2, 300, days: 1, sport_id: 9),
      effort(3, 590, days: 2, sport_id: 7)
    ])

    expect(history.chartable_series.map(&:sport_id)).to eq([ 7 ])
    expect(described_class.new([ effort(1, 600, days: 0, sport_id: 7), effort(2, 300, days: 1, sport_id: 9) ]))
      .not_to be_chartable
  end
end
