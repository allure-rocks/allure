# frozen_string_literal: true

require "rails_helper"

RSpec.describe BestEfforts::Rebuild do
  let(:user) { create(:user) }

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

  def workout_with_track(sport, distance: 5_000, step: 100, seconds_per_step: 10)
    workout = create(:workout, user:, sport:, distance: distance.to_f)
    create(:track_segment, workout:, distance: distance.to_f,
                           points: points_for(distance:, step:, seconds_per_step:))
    workout
  end

  it "persists one effort per covered distance" do
    running = catalog_sport("running")
    workout = workout_with_track(running)

    described_class.new(workout:).call

    five = workout.best_efforts.find_by!(distance_key: "km5")
    expect(five.duration_seconds).to eq(500)
    expect(five.distance_meters).to eq(5_000.0)
    expect(five.started_at).to eq(workout.started_at)
    expect(workout.best_efforts.find_by(distance_key: "mi50")).to be_nil
  end

  it "drops an effort the GPS lengthened by an anomaly" do
    running = catalog_sport("running")
    workout = workout_with_track(running)
    workout.update!(data_anomalies: { "findings" => [
      { "kind" => "gps_jump", "start_distance" => 4_500.0, "end_distance" => 4_600.0, "detail" => { "excess" => 60 } }
    ], "counts" => { "gps_jump" => 1 } })

    described_class.new(workout:).call

    expect(workout.best_efforts.find_by(distance_key: "km5")).to be_nil
    expect(workout.best_efforts.find_by(distance_key: "km1")).to be_present
  end

  it "is idempotent" do
    running = catalog_sport("running")
    workout = workout_with_track(running)

    described_class.new(workout:).call
    first = workout.best_efforts.order(:distance_key).pluck(:distance_key, :duration_seconds)
    described_class.new(workout:).call

    expect(workout.best_efforts.order(:distance_key).pluck(:distance_key, :duration_seconds)).to eq(first)
  end

  it "replaces rows when the track changes" do
    running = catalog_sport("running")
    workout = workout_with_track(running, seconds_per_step: 20)
    described_class.new(workout:).call
    expect(workout.best_efforts.find_by!(distance_key: "km1").duration_seconds).to eq(200)

    workout.track_segments.delete_all
    create(:track_segment, workout:, distance: 5_000.0,
                           points: points_for(distance: 5_000, step: 100, seconds_per_step: 10))
    described_class.new(workout:).call

    expect(workout.best_efforts.find_by!(distance_key: "km1").duration_seconds).to eq(100)
  end

  it "persists nothing for a sport without an effort profile" do
    other = create(:sport)
    workout = create(:workout, user:, sport: other)
    create(:track_segment, workout:, distance: 5_000.0,
                           points: points_for(distance: 5_000, step: 100, seconds_per_step: 10))

    described_class.new(workout:).call

    expect(workout.best_efforts.count).to eq(0)
  end

  it "persists the rowing standard distances" do
    rowing = catalog_sport("rowing")
    workout = workout_with_track(rowing, distance: 6_000)

    described_class.new(workout:).call

    keys = workout.best_efforts.order(:distance_meters).pluck(:distance_key)
    expect(keys).to eq(%w[m500 km1 km2 km5 km6])
    expect(workout.best_efforts.find_by!(distance_key: "km2").duration_seconds).to eq(200)
  end

  it "computes without writing so the caller can persist inside its transaction" do
    running = catalog_sport("running")
    workout = workout_with_track(running)

    efforts = described_class.compute(
      sport: running,
      segments: workout.track_segments.reload,
      workout_started_at: workout.started_at,
      context: "import"
    )

    expect(efforts.map(&:distance_key)).to include("km5")
    expect(workout.best_efforts.count).to eq(0)

    described_class.new(workout:, context: "import").persist(efforts)

    expect(workout.best_efforts.find_by!(distance_key: "km5").duration_seconds).to eq(500)
  end

  it "times the compute and persist phases on the metric" do
    running = catalog_sport("running")
    workout = workout_with_track(running)

    described_class.new(workout:, context: "import").call

    metric = Yabeda.allure.best_efforts_rebuild_duration_seconds
    %w[compute persist].each do |phase|
      labels = Yabeda::Tags.build({ phase:, context: "import" }, :allure)
      expect(metric.values[labels]).to be_a(Float).and be >= 0.0
    end
  end
end
