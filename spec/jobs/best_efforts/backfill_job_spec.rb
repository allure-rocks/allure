# frozen_string_literal: true

require "rails_helper"

RSpec.describe BestEfforts::BackfillJob do
  def points_for(distance:, step:, seconds_per_step:)
    (0..(distance / step).round).map do |index|
      metres = index * step
      {
        "t" => index * seconds_per_step,
        "d" => metres.to_f,
        "lat" => 45.0 + (metres / 111_320.0),
        "lon" => 6.0,
        "ele" => 100.0
      }
    end
  end

  it "rebuilds efforts and effort records for existing workouts" do
    user = create(:user)
    running = catalog_sport("running")
    workout = create(:workout, user:, sport: running, distance: 5_000.0)
    create(:track_segment, workout:, distance: 5_000.0,
                           points: points_for(distance: 5_000, step: 100, seconds_per_step: 10))
    expect(workout.best_efforts.count).to eq(0)

    described_class.perform_now

    expect(workout.best_efforts.count).to be > 0
    expect(EffortRecord.find_by(user:, sport: running, distance_key: "km5")).to be_present
  end

  it "skips sports without an effort profile" do
    user = create(:user)
    other = create(:sport)
    workout = create(:workout, user:, sport: other, distance: 5_000.0)
    create(:track_segment, workout:, distance: 5_000.0,
                           points: points_for(distance: 5_000, step: 100, seconds_per_step: 10))

    described_class.perform_now

    expect(workout.best_efforts.count).to eq(0)
  end

  it "rebuilds the rowing standard distances and their records" do
    user = create(:user)
    rowing = catalog_sport("rowing")
    workout = create(:workout, user:, sport: rowing, distance: 2_000.0)
    create(:track_segment, workout:, distance: 2_000.0,
                           points: points_for(distance: 2_000, step: 100, seconds_per_step: 10))

    described_class.perform_now

    expect(workout.best_efforts.pluck(:distance_key)).to include("m500", "km1", "km2")
    expect(EffortRecord.find_by(user:, sport: rowing, distance_key: "km2")).to be_present
  end

  it "narrows the sweep to one sport" do
    user = create(:user)
    running = catalog_sport("running")
    rowing = catalog_sport("rowing")
    running_workout = create(:workout, user:, sport: running, distance: 5_000.0)
    create(:track_segment, workout: running_workout, distance: 5_000.0,
                           points: points_for(distance: 5_000, step: 100, seconds_per_step: 10))
    rowing_workout = create(:workout, user:, sport: rowing, distance: 2_000.0)
    create(:track_segment, workout: rowing_workout, distance: 2_000.0,
                           points: points_for(distance: 2_000, step: 100, seconds_per_step: 10))

    described_class.perform_now(sport_slug: "rowing")

    expect(rowing_workout.best_efforts.count).to be > 0
    expect(running_workout.best_efforts.count).to eq(0)
  end
end
