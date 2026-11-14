# frozen_string_literal: true

require "rails_helper"

RSpec.describe HeartRates::History do
  let(:user) { create(:user, max_heart_rate: 190, time_zone: "Europe/Paris", week_start: "monday") }
  let(:running) { catalog_sport("running") }
  let(:cycling) { catalog_sport("cycling") }

  # 600 s at 120 bpm (Z2) and 600 s at 176 bpm (Z5): load 10×2 + 10×5 = 70.
  def recording(started_at:, sport: running, owner: user, heart_rate: true)
    workout = create(:workout, user: owner, sport:, started_at:)
    points = (0..60).map do |index|
      point = { "t" => index * 20, "d" => index * 40.0, "lat" => 45.07 + (index * 0.0001), "lon" => 6.40 }
      point["hr"] = index < 30 ? 120 : 176 if heart_rate
      point
    end
    create(:track_segment, workout:, points:)
    HeartRates::Rebuild.new(workout:).call
    workout
  end

  it "sums the loads per calendar day of the account" do
    recording(started_at: Time.utc(2026, 10, 12, 22, 30)) # 13 Oct in Paris
    recording(started_at: Time.utc(2026, 10, 13, 8))

    expect(described_class.new(user:).daily_loads).to eq(Date.new(2026, 10, 13) => 140.0)
  end

  it "totals the zones per week or month, for one sport or all" do
    recording(started_at: Time.zone.parse("2026-10-13 08:00"))
    recording(started_at: Time.zone.parse("2026-10-14 08:00"), sport: cycling)
    recording(started_at: Time.zone.parse("2026-09-30 08:00"))
    history = described_class.new(user:)

    weeks = history.zone_totals(granularity: "week", from: Date.new(2026, 10, 1), through: Date.new(2026, 10, 20))
    expect(weeks).to eq([
      { period: Date.new(2026, 9, 28), seconds: [ 0, 0, 0, 0, 0 ] },
      { period: Date.new(2026, 10, 5), seconds: [ 0, 0, 0, 0, 0 ] },
      { period: Date.new(2026, 10, 12), seconds: [ 0, 1200, 0, 0, 1200 ] },
      { period: Date.new(2026, 10, 19), seconds: [ 0, 0, 0, 0, 0 ] }
    ])
    expect(history.zone_totals(granularity: "week", from: Date.new(2026, 11, 1), through: Date.new(2026, 11, 30))).to eq([])

    months = history.zone_totals(granularity: "month", from: Date.new(2026, 9, 1), through: Date.new(2026, 10, 31),
                                                       sport_id: running.id)
    expect(months.map { it[:period] }).to eq([ Date.new(2026, 9, 1), Date.new(2026, 10, 1) ])
    expect(months.last[:seconds]).to eq([ 0, 600, 0, 0, 600 ])
  end

  it "slices rows the rezone job has not reached under the current zones" do
    recording(started_at: Time.zone.parse("2026-10-13 08:00"))
    user.update!(max_heart_rate: 200) # 176 bpm becomes Z4 (≥ 160), 120 bpm Z2 (≥ 120)

    history = described_class.new(user: user.reload)

    totals = history.zone_totals(granularity: "week", from: Date.new(2026, 10, 12), through: Date.new(2026, 10, 18))
    expect(totals.first[:seconds]).to eq([ 0, 600, 0, 600, 0 ])
    expect(history.daily_loads.values).to eq([ 60.0 ])
  end

  it "reads nothing without a profile, and counts the sessions without heart rate" do
    recording(started_at: Time.zone.parse("2026-10-13 08:00"))
    recording(started_at: Time.zone.parse("2026-10-14 08:00"), heart_rate: false)
    create(:workout, :manual, user:, started_at: Time.zone.parse("2026-10-15 08:00"))
    recording(started_at: Time.zone.parse("2026-10-13 08:00"), owner: create(:user, max_heart_rate: 180))

    history = described_class.new(user:)
    expect(history).to be_any
    expect(history.workouts_without_heart_rate(from: Date.new(2026, 10, 1), to: Date.new(2026, 10, 31))).to eq(2)

    user.update!(max_heart_rate: nil)
    expect(described_class.new(user:).daily_loads).to be_empty
  end

  it "counts the recordings whose heart rate covers only part of their time, without imputing their load" do
    workout = create(:workout, user:, started_at: Time.zone.parse("2026-10-13 08:00"))
    points = (0..100).map do |index|
      { "t" => index * 10, "d" => index * 40.0, "lat" => 45.07, "lon" => 6.40 }.tap { it["hr"] = 150 + (index % 3) if index < 70 }
    end
    create(:track_segment, workout:, points:)
    HeartRates::Rebuild.new(workout:).call
    recording(started_at: Time.zone.parse("2026-10-14 08:00"))
    history = described_class.new(user:)

    expect(history.partial_workouts(from: Date.new(2026, 10, 1), to: Date.new(2026, 10, 31))).to eq(1)
    # The load counts the 700 s that carry a heart rate, nothing for the rest.
    expect(history.daily_loads[Date.new(2026, 10, 13)]).to eq(workout.heart_rate.load.to_f)
    expect(workout.heart_rate.coverage).to be_within(0.001).of(0.7)
  end
end
