# frozen_string_literal: true

require "rails_helper"

RSpec.describe DetectedLap do
  it "accepts the full source catalog and rejects anything else" do
    expect(described_class::SOURCES).to eq(
      %w[loop route pause climb descent stop speed_interval power_interval]
    )
    expect(build(:detected_lap, source: "smart")).not_to be_valid
  end

  it "enforces one number per workout and source" do
    lap = create(:detected_lap)
    duplicate = build(:detected_lap, workout: lap.workout, source: lap.source, number: lap.number)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:number]).to be_present
  end

  it "rejects a reversed point range and a negative moving time" do
    expect(build(:detected_lap, start_point_index: 3, end_point_index: 1)).not_to be_valid
    expect(build(:detected_lap, elapsed_time: 60, moving_time: 90)).not_to be_valid
  end

  it "scopes laps apart from climbs" do
    workout = create(:workout)
    create(:detected_lap, :loop, workout:)
    create(:detected_lap, :climb, workout:, number: 1)

    expect(workout.detected_laps.laps.pluck(:source)).to eq([ "loop" ])
    expect(workout.detected_laps.climbs.pluck(:source)).to eq([ "climb" ])
  end

  it "cascades with its workout" do
    lap = create(:detected_lap)

    expect { lap.workout.destroy! }.to change(described_class, :count).by(-1)
  end

  it "nullifies the effort reference when the effort dies" do
    workout = create(:workout)
    effort = create(:segment_effort, workout:, user: workout.user, sport: workout.sport)
    lap = create(:detected_lap, :loop, workout:, segment_effort: effort)

    effort.destroy!

    expect(lap.reload.segment_effort_id).to be_nil
  end
end
