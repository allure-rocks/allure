# frozen_string_literal: true

require "rails_helper"

RSpec.describe Laps::Rebuild do
  def import_three_laps(user, sport)
    file = ActionDispatch::Http::UploadedFile.new(
      tempfile: File.open(Rails.root.join("spec/fixtures/gpx/three_laps.gpx")),
      filename: "three_laps.gpx",
      type: "application/gpx+xml"
    )
    Workouts::Importer.new(user:, sport:, uploaded_file: file).call.workout
  end

  def climb_points
    (0..22).map do |index|
      distance = index * 100.0
      elevation = case distance
      when 0...600 then 100.0
      when 600..1_600 then 100.0 + ((distance - 600.0) * 0.1)
      else 180.0
      end
      { "t" => index * 60, "d" => distance, "lat" => 45.0 + (index * 0.0001), "lon" => 6.4, "ele" => elevation }
    end
  end

  def build_speed_points(speeds)
    distance = 0.0
    points = [ { "t" => 0, "d" => 0.0, "lat" => 45.0, "lon" => 6.4, "ele" => 100.0 } ]
    speeds.each_with_index do |speed, index|
      distance += speed * 10.0
      points << { "t" => (index + 1) * 10, "d" => distance, "lat" => 45.0, "lon" => 6.4, "ele" => 100.0 }
    end
    points
  end

  def build_power_points(powers)
    distance = 0.0
    points = [ { "t" => 0, "d" => 0.0, "lat" => 45.0, "lon" => 6.4, "ele" => 100.0, "pw" => powers.first } ]
    powers.each_with_index do |power, index|
      distance += 50.0
      points << { "t" => (index + 1) * 10, "d" => distance, "lat" => 45.0, "lon" => 6.4, "ele" => 100.0, "pw" => power }
    end
    points
  end

  it "projects loop efforts into detected laps" do
    user = create(:user)
    sport = create(:sport)
    workout = import_three_laps(user, sport)
    Segments::MatchWorkoutJob.perform_now(workout)

    laps = workout.detected_laps.where(source: "loop").order(:number)

    expect(laps.pluck(:number)).to eq([ 1, 2, 3 ])
    expect(laps).to all(have_attributes(segment_effort_id: be_present))
    expect(laps.first.start_distance).to be < laps.first.end_distance
    expect(laps.last.end_distance).to be <= workout.distance + 1.0
  end

  it "creates one pause lap per recording segment with global point indexes" do
    workout = create(:workout)
    create(:track_segment, workout:, position: 0)
    create(:track_segment, workout:, position: 1,
      started_at: workout.started_at + 120.seconds,
      points: [
        { "t" => 0, "d" => 0.0, "lat" => 45.0728, "lon" => 6.4092, "ele" => 112.0 },
        { "t" => 90, "d" => 300.0, "lat" => 45.0746, "lon" => 6.4110, "ele" => 118.0 }
      ],
      distance: 300.0, duration: 90, moving_time: 80, pause_time: 10)

    described_class.new(workout:).call

    laps = workout.detected_laps.where(source: "pause").order(:start_distance)
    expect(laps.length).to eq(2)
    expect(laps.map { |lap| [ lap.start_point_index, lap.end_point_index ] }).to eq([ [ 0, 1 ], [ 2, 3 ] ])
    expect(laps.last.start_distance).to eq(250.0)
    expect(laps.last.end_distance).to eq(550.0)
  end

  it "detects climbs from the elevation profile" do
    workout = create(:workout)
    points = climb_points
    create(:track_segment, workout:,
      points:, distance: 2_200.0, duration: 1_320, moving_time: 1_320, pause_time: 0,
      ascent: 80.0, descent: 0.0, min_elevation: 100.0, max_elevation: 180.0,
      average_speed: 1.67, max_speed: 2.0, average_pace: 599)

    described_class.new(workout:).call

    climb = workout.detected_laps.find_by(source: "climb")
    expect(climb).to be_present
    expect(climb.distance).to be_within(10.0).of(1_000.0)
    expect(climb.ascent).to be_within(15.0).of(90.0)
    expect(climb.average_grade).to be_within(1.0).of(9.5)
    expect(climb.climb_score).to be_positive
  end

  it "projects a repeated route into one lap per traversal" do
    user = create(:user)
    sport = create(:sport)
    workout = create(:workout, user:, sport:)
    create(:track_segment, workout:,
      points: [
        { "t" => 0, "d" => 0.0, "lat" => 45.0, "lon" => 6.0, "ele" => 100.0 },
        { "t" => 60, "d" => 250.0, "lat" => 45.001, "lon" => 6.001, "ele" => 105.0 },
        { "t" => 120, "d" => 500.0, "lat" => 45.002, "lon" => 6.002, "ele" => 110.0 },
        { "t" => 180, "d" => 750.0, "lat" => 45.003, "lon" => 6.003, "ele" => 115.0 }
      ],
      distance: 750.0, duration: 180, moving_time: 170, pause_time: 10)
    route = create(:segment, :route, user:, sport:)
    create(:segment_effort, segment: route, workout:, user:, sport:,
      occurrence_index: 0, start_point_index: 0, end_point_index: 1)
    create(:segment_effort, segment: route, workout:, user:, sport:,
      occurrence_index: 1, start_point_index: 2, end_point_index: 3)

    described_class.new(workout:).call

    laps = workout.detected_laps.where(source: "route").order(:number)
    expect(laps.pluck(:number)).to eq([ 1, 2 ])
    expect(laps.pluck(:segment_effort_id)).to all(be_present)
  end

  it "does not project a route traversed only once" do
    user = create(:user)
    sport = create(:sport)
    workout = create(:workout, user:, sport:)
    create(:track_segment, workout:)
    route = create(:segment, :route, user:, sport:)
    create(:segment_effort, segment: route, workout:, user:, sport:)

    described_class.new(workout:).call

    expect(workout.detected_laps.where(source: "route")).to be_empty
  end

  it "drops a pause lap overlapped by a loop lap" do
    user = create(:user)
    sport = create(:sport)
    workout = create(:workout, user:, sport:)
    create(:track_segment, workout:, position: 0)
    create(:track_segment, workout:, position: 1)
    loop_segment = create(:segment, :loop, user:, sport:)
    create(:segment_effort, segment: loop_segment, workout:, user:, sport:,
      start_point_index: 0, end_point_index: 1)

    described_class.new(workout:).call

    expect(workout.detected_laps.pluck(:source)).to contain_exactly("loop", "pause")
    pause = workout.detected_laps.find_by(source: "pause")
    expect(pause.start_distance).to eq(250.0)
  end

  it "is idempotent and rebuilds identical rows" do
    user = create(:user)
    sport = create(:sport)
    workout = import_three_laps(user, sport)
    Segments::MatchWorkoutJob.perform_now(workout)
    signature = lambda do
      workout.detected_laps.order(:source, :number).pluck(:source, :number, :distance, :start_distance, :end_distance)
    end
    before = signature.call

    described_class.new(workout:).call

    expect(signature.call).to eq(before)
  end

  it "names detected laps from a ready toponymy" do
    workout = create(:workout)
    create(:track_segment, workout:, position: 0)
    create(:track_segment, workout:, position: 1)
    create(:workout_toponymy, workout:, markers: [
      { "distance" => 120.0, "name" => "Parc Blandan", "kind" => "landmark", "rank" => 1 }
    ])

    described_class.new(workout:).call

    expect(workout.detected_laps.find_by(source: "pause", number: 1).name).to eq("Parc Blandan")
  end

  it "detects a descent from the inverted elevation profile" do
    workout = create(:workout)
    points = (0..22).map do |index|
      distance = index * 100.0
      elevation = case distance
      when 0...600 then 200.0
      when 600..1_600 then 200.0 - ((distance - 600.0) * 0.1)
      else 100.0
      end
      { "t" => index * 60, "d" => distance, "lat" => 45.0 + (index * 0.0001), "lon" => 6.4, "ele" => elevation }
    end
    create(:track_segment, workout:,
      points:, distance: 2_200.0, duration: 1_320, moving_time: 1_320, pause_time: 0,
      ascent: 0.0, descent: 100.0, min_elevation: 100.0, max_elevation: 200.0,
      average_speed: 1.67, max_speed: 2.0, average_pace: 599)

    described_class.new(workout:).call

    descent = workout.detected_laps.find_by(source: "descent")
    expect(descent).to be_present
    expect(descent.descent).to be_within(15.0).of(100.0)
    expect(descent.average_grade).to be_within(1.0).of(9.5)
    expect(workout.detected_laps.where(source: "climb")).to be_empty
  end

  it "detects a stop inside one recording segment" do
    workout = create(:workout)
    distance = 0.0
    distances = []
    6.times { distances << distance; distance += 30.0 }
    6.times { distances << distance }
    6.times { distances << distance; distance += 30.0 }
    points = distances.each_with_index.map do |value, index|
      { "t" => index * 10, "d" => value, "lat" => 45.0, "lon" => 6.4, "ele" => 100.0 }
    end
    create(:track_segment, workout:,
      points:, distance: distances.last, duration: 170, moving_time: 110, pause_time: 60,
      ascent: 0.0, descent: 0.0, min_elevation: 100.0, max_elevation: 100.0,
      average_speed: 1.76, max_speed: 3.0, average_pace: 568)

    described_class.new(workout:).call

    stop = workout.detected_laps.find_by(source: "stop")
    expect(stop).to be_present
    expect(stop.elapsed_time).to eq(60)
  end

  it "detects sustained speed intervals" do
    workout = create(:workout)
    points = build_speed_points(Array.new(60, 2.0) + Array.new(60, 8.0) + Array.new(60, 2.0))
    create(:track_segment, workout:,
      points:, distance: points.last.fetch("d"), duration: 1_800, moving_time: 1_800, pause_time: 0,
      ascent: 0.0, descent: 0.0, min_elevation: 100.0, max_elevation: 100.0,
      average_speed: 4.0, max_speed: 8.0, average_pace: 250)

    described_class.new(workout:).call

    interval = workout.detected_laps.find_by(source: "speed_interval")
    expect(interval).to be_present
    expect(interval.distance).to be_within(320.0).of(4_800.0)
  end

  # A positionless recording (docs/dev/NO-GPS.md) has no gradient: even when
  # its sport would normally carry a grade-adjusted pace, its derived speed
  # intervals are built without one instead of crashing on nil coordinates.
  it "derives speed intervals without grade-adjusted pace for a positionless recording" do
    workout = create(:workout, :unpositioned, sport: catalog_sport("running"))
    points = build_speed_points(Array.new(60, 2.0) + Array.new(60, 8.0) + Array.new(60, 2.0))
              .map { |point| point.except("lat", "lon") }
    create(:track_segment, :unpositioned, workout:,
      points:, distance: points.last.fetch("d"), duration: 1_800, moving_time: 1_800, pause_time: 0,
      ascent: 0.0, descent: 0.0, min_elevation: nil, max_elevation: nil,
      average_speed: 4.0, max_speed: 8.0, average_pace: 250)

    expect { described_class.new(workout:).call }.not_to raise_error

    interval = workout.detected_laps.find_by(source: "speed_interval")
    expect(interval).to be_present
    expect(interval.grade_adjusted_pace).to be_nil
  end

  # A duration-only session (docs/dev/NO-GPS.md) records neither speed nor
  # distance: its flat distance is an absence of data, not a standstill.
  it "detects no stop or speed interval for a workout with no movement signal" do
    workout = create(:workout, :unpositioned)
    points = 6.times.map { |index| { "t" => index * 300, "d" => 0.0, "hr" => 100 + index } }
    create(:track_segment, :unpositioned, workout:,
      points:, distance: 0.0, duration: 1_500, moving_time: 1_500, pause_time: 0,
      average_speed: 0.0, max_speed: nil, average_pace: nil, best_pace: nil,
      average_heart_rate: 102)

    described_class.new(workout:).call

    expect(workout.detected_laps.pluck(:source)).to be_empty
  end

  it "detects power intervals only for a sport that records power" do
    sport = create(:sport, colour_group: "ride", records_power: true)
    workout = create(:workout, sport:)
    points = build_power_points(Array.new(60, 100.0) + Array.new(60, 300.0) + Array.new(60, 100.0))
    create(:track_segment, workout:,
      points:, distance: points.last.fetch("d"), duration: 1_800, moving_time: 1_800, pause_time: 0,
      ascent: 0.0, descent: 0.0, min_elevation: 100.0, max_elevation: 100.0,
      average_speed: 5.0, max_speed: 5.0, average_pace: 200)

    described_class.new(workout:).call

    expect(workout.detected_laps.where(source: "power_interval").count).to eq(1)
  end
end
