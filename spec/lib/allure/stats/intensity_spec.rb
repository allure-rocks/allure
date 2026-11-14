# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Stats::Intensity do
  def row(period, workouts: 0, distance: 0.0, duration: 0, ascent: 0.0, sports: {})
    { period: Date.new(2026, 9, period), workouts:, distance:, duration:, ascent:, sports: }
  end

  it "scores the strongest bucket 100 and the others as their mean share of it" do
    intensity = described_class.new([
      row(1, workouts: 1, distance: 10_000.0, duration: 3600, ascent: 400.0),
      row(2, workouts: 1, distance: 5_000.0, duration: 1800, ascent: 200.0),
      row(3, workouts: 2, distance: 10_000.0, duration: 1800, ascent: 0.0)
    ])

    expect(intensity.rows.map { |r| r[:score] }).to eq([ 100, 50, 50 ])
    expect(intensity.components).to eq(%i[duration distance ascent])
  end

  it "rescales so the strongest bucket is 100 even when no bucket leads every component" do
    intensity = described_class.new([
      row(1, workouts: 1, distance: 5_000.0, duration: 3600),
      row(2, workouts: 1, distance: 10_000.0, duration: 1800),
      row(3, workouts: 1, distance: 5_000.0, duration: 1800)
    ])

    expect(intensity.rows.map { |r| r[:score] }).to eq([ 100, 100, 67 ])
    expect(intensity.peak[:period]).to eq(Date.new(2026, 9, 1))
  end

  it "marks buckets without a workout as rest with a zero score" do
    intensity = described_class.new([ row(1, workouts: 1, distance: 1000.0, duration: 600), row(2) ])

    expect(intensity.rows.last).to include(rest: true, score: 0, workouts: 0)
    expect(intensity.rows.first).to include(rest: false, score: 100)
  end

  it "leaves out a component nobody recorded in the window" do
    intensity = described_class.new([
      row(1, workouts: 1, distance: 2000.0, duration: 1200),
      row(2, workouts: 1, distance: 1000.0, duration: 1200)
    ])

    expect(intensity.components).to eq(%i[duration distance])
    expect(intensity.rows.map { |r| r[:score] }).to eq([ 100, 75 ])
  end

  it "never scores an active bucket below 1" do
    intensity = described_class.new([
      row(1, workouts: 1, distance: 100_000.0, duration: 36_000, ascent: 3000.0),
      row(2, workouts: 1, distance: 10.0, duration: 1)
    ])

    expect(intensity.rows.last[:score]).to eq(1)
  end

  it "names the earliest strongest bucket as the peak and counts the active ones" do
    intensity = described_class.new([
      row(1),
      row(2, workouts: 1, distance: 5000.0, duration: 1800),
      row(3, workouts: 1, distance: 5000.0, duration: 1800),
      row(4)
    ])

    expect(intensity.peak[:period]).to eq(Date.new(2026, 9, 2))
    expect(intensity.active_count).to eq(2)
    expect(intensity.total_count).to eq(4)
  end

  it "has no peak and no components on an empty or idle window" do
    expect(described_class.new([]).peak).to be_nil
    idle = described_class.new([ row(1), row(2) ])
    expect(idle.peak).to be_nil
    expect(idle.components).to be_empty
    expect(idle.rows.map { |r| r[:score] }).to eq([ 0, 0 ])
  end

  it "carries the bucket facts through for the detail line" do
    intensity = described_class.new([ row(1, workouts: 2, distance: 12_345.6, duration: 5400, ascent: 321.0) ])

    expect(intensity.rows.first).to include(
      period: Date.new(2026, 9, 1), workouts: 2, distance: 12_345.6, duration: 5400, ascent: 321.0
    )
  end

  it "counts the distinct sports of each week" do
    intensity = described_class.new([
      row(1, workouts: 2, distance: 1000.0, duration: 600, sports: { 1 => {}, 2 => {} }),
      row(2, workouts: 1, distance: 1000.0, duration: 600, sports: { 1 => {} }),
      row(3)
    ])

    expect(intensity.rows.map { |entry| entry[:sports] }).to eq([ 2, 1, 0 ])
  end

  it "scopes the peak and the counts to the weeks overlapping a period range" do
    intensity = described_class.new([
      row(7),
      row(14, workouts: 1, distance: 2_000.0, duration: 1_800),
      row(21, workouts: 1, distance: 5_000.0, duration: 1_800),
      row(28)
    ])

    range = Date.new(2026, 9, 17)..Date.new(2026, 9, 24)

    expect(intensity.within(range).map { |entry| entry[:period] }).to eq([ Date.new(2026, 9, 14), Date.new(2026, 9, 21) ])
    expect(intensity.peak(range)[:period]).to eq(Date.new(2026, 9, 21))
    expect(intensity.active_count(range)).to eq(2)
    expect(intensity.total_count(range)).to eq(2)
  end

  it "keeps the whole series when no range is given" do
    intensity = described_class.new([ row(7), row(14) ])

    expect(intensity.within).to eq(intensity.rows)
    expect(intensity.total_count).to eq(2)
  end
end
