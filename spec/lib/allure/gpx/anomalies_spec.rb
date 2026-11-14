# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Gpx::Anomalies do
  let(:started_at) { Time.zone.parse("2026-06-01 08:00:00 UTC") }
  let(:metres_per_latitude_degree) { 111_319.49 }

  def latitude_at(metres) = 45.0 + (metres / metres_per_latitude_degree)

  # A straight ride north at `metres_per_second`, one point per second unless
  # `times` says otherwise. Positions follow the given distances.
  def track(count: 300, metres_per_second: 8.0, distances: nil, times: nil, **readings)
    distances ||= Array.new(count) { |index| index * metres_per_second }
    times ||= Array.new(count) { |index| index.to_f }
    distances.each_index.map do |index|
      Allure::Gpx::Point.new(
        time: started_at + times[index],
        latitude: latitude_at(distances[index]),
        longitude: 6.0,
        elevation: readings[:elevations]&.[](index),
        heart_rate: readings[:heart_rates]&.[](index),
        cadence: readings[:cadences]&.[](index),
        power: readings[:powers]&.[](index)
      )
    end
  end

  def analyze(points, speed_ceiling_km_h: nil)
    Allure::Gpx::Analyzer.new(stopped_speed_threshold_km_h: 1.0, speed_ceiling_km_h:)
      .analyze(Allure::Gpx::Track.new(segments: [ Allure::Gpx::Segment.new(points:) ]))
      .anomalies
  end

  def kinds(result) = result.fetch("findings", []).map { |finding| finding["kind"] }

  it "reports nothing for a clean recording" do
    expect(analyze(track(heart_rates: Array.new(300) { |index| 130 + (index % 7) }))).to eq({})
  end

  it "reports a rejected position with its coordinates and the path through it" do
    points = track
    points[150] = points[150].with(longitude: 6.002)

    finding = analyze(points)["findings"].find { |entry| entry["kind"] == "gps_rejected" }

    expect(finding["coordinates"]).to eq([ [ 6.002, points[150].latitude.round(6) ] ])
    expect(finding["path"].length).to eq(3)
    expect(finding["start_distance"]).to be_within(1).of(149 * 8.0)
  end

  it "reports a sample stamped a second late as a shifted timestamp, not a GPS jump" do
    times = (0...300).map(&:to_f) - [ 152.0 ]
    distances = times.map { |second| second * 8.0 }
    distances[151] = 152 * 8.0

    result = analyze(track(distances:, times:))

    expect(kinds(result)).to eq(%w[timestamp_skew])
    expect(result["findings"].first["detail"]["corrected"]).to be_within(1).of(28.8)
  end

  it "reports a position jump that the outlier stage keeps" do
    distances = Array.new(300) { |index| index * 2.0 }
    (150...300).each { |index| distances[index] += 60.0 }

    expect(kinds(analyze(track(distances:)))).to include("gps_jump")
  end

  it "reports a speed the sport cannot reach and keeps a genuine fast descent" do
    expect(kinds(analyze(track(metres_per_second: 19.0), speed_ceiling_km_h: 120.0))).not_to include("speed_implausible")
    expect(kinds(analyze(track(metres_per_second: 13.0), speed_ceiling_km_h: 20.0))).to include("speed_implausible")
  end

  it "reports a recording interrupted while moving but not a real stop" do
    moving = Array.new(300) { |index| index < 150 ? index.to_f : index + 30.0 }
    moving_distances = Array.new(300) { |index| index < 150 ? index * 8.0 : index * 8.0 + 240.0 }
    stopped_distances = Array.new(300) { |index| index * 8.0 }

    expect(kinds(analyze(track(times: moving, distances: moving_distances)))).to include("recording_gap")
    expect(kinds(analyze(track(times: moving, distances: stopped_distances)))).not_to include("recording_gap")
  end

  it "reports a held heart rate followed by a dropout as one frozen reading" do
    rates = Array.new(300) { |index| 140 + (index % 5) }
    (100...118).each { |index| rates[index] = 163 }
    (118...140).each { |index| rates[index] = nil }

    result = analyze(track(heart_rates: rates))

    expect(kinds(result)).to eq(%w[hr_frozen])
    expect(result["findings"].first["detail"]).to include("bpm" => 163, "frozen" => 18, "missing" => 22)
  end

  it "reports a late heart rate sensor and ignores the short holes of a sparse one" do
    late = Array.new(300) { |index| index < 60 ? nil : 140 }
    sparse = Array.new(300) { |index| (index % 4).zero? ? 140 : nil }

    expect(analyze(track(heart_rates: late))["findings"].first["detail"]).to include("position" => "start", "seconds" => 60)
    expect(kinds(analyze(track(heart_rates: sparse)))).not_to include("hr_missing")
  end

  it "reports a sudden heart rate drop that holds until the reading recovers" do
    rates = Array.new(300) { 155 }
    (150...180).each { |index| rates[index] = 116 + (index - 150) }

    finding = analyze(track(heart_rates: rates))["findings"].find { |entry| entry["kind"] == "hr_jump" }

    expect(finding["detail"]).to include("from" => 155, "to" => 116)
    expect(finding["end_time"]).to be >= 175
  end

  it "reports elevation, power and cadence spikes" do
    elevations = Array.new(300) { 100.0 }
    elevations[200] = 160.0
    powers = Array.new(300) { 220 }
    powers[100] = 2_100
    cadences = Array.new(300) { 88 }
    cadences[120] = 255

    expect(kinds(analyze(track(elevations:, powers:, cadences:))))
      .to include("elevation_step", "power_spike", "cadence_spike")
  end

  it "merges close findings of one kind into one range with a count" do
    powers = Array.new(300) { 220 }
    powers[100] = 2_600
    powers[104] = 2_800

    finding = analyze(track(powers:))["findings"].find { |entry| entry["kind"] == "power_spike" }

    expect(finding["detail"]).to include("value" => 2_800, "count" => 2)
  end

  describe "impact" do
    # A walk at 1.5 m/s whose GPS throws one position 200 m ahead for a few
    # seconds: the maximum speed and the distance both read the jump.
    def walk_with_jump(speeds: nil)
      distances = Array.new(600) { |index| index * 1.5 }
      (300...304).each { |index| distances[index] += 200.0 }
      points = track(count: 600, distances:)
      speeds ? points.each_with_index.map { |point, index| point.with(speed: speeds[index]) } : points
    end

    def analyze_walk(points)
      Allure::Gpx::Analyzer.new(stopped_speed_threshold_km_h: 1.0, speed_ceiling_km_h: 20.0)
        .analyze(Allure::Gpx::Track.new(segments: [ Allure::Gpx::Segment.new(points:) ]))
        .anomalies
    end

    it "marks a finding that inflates the maximum speed as major, with a plausible value" do
      result = analyze_walk(walk_with_jump)

      expect(result["impact"]["max_speed"]).to include("basis" => "track")
      expect(result["impact"]["max_speed"]["plausible"]).to be < 3.0
      expect(result["findings"].select { |finding| finding["tier"] == "major" }).not_to be_empty
      expect(described_class.contested_columns(result)).to include("max_speed", "best_pace")
    end

    it "takes the plausible maximum from the device's own speed when the file carries it" do
      result = analyze_walk(walk_with_jump(speeds: Array.new(600) { 1.6 }))

      expect(result["impact"]["max_speed"]).to include("basis" => "device", "plausible" => 1.6)
    end

    it "leaves an ordinary recording's findings minor" do
      powers = Array.new(300) { 220 }
      powers[100] = 2_100

      result = analyze(track(powers:))

      expect(result["findings"].map { |finding| finding["tier"] }).to all(eq("minor"))
      expect(result).not_to have_key("impact")
      expect(described_class.contested_columns(result)).to eq([])
    end

    it "contests an effort only when the added distance reaches 1 % of it" do
      data = { "findings" => [ { "kind" => "gps_jump", "start_distance" => 500.0, "end_distance" => 520.0,
                                 "detail" => { "excess" => 15 } } ] }

      expect(described_class.contested_effort?(data, start_distance: 0.0, end_distance: 1_000.0)).to be(true)
      expect(described_class.contested_effort?(data, start_distance: 0.0, end_distance: 5_000.0)).to be(false)
      expect(described_class.contested_effort?(data, start_distance: 600.0, end_distance: 1_600.0)).to be(false)
    end

    # An out-and-back of `leg` metres ridden at 5 m/s, the return reading
    # `gap_metres` higher: the two passages stand on the same ground.
    def out_and_back(gap_metres:, leg: 3_000.0)
      out = (0..(leg / 20).round).map do |index|
        metres = index * 20.0
        Allure::Gpx::Point.new(time: started_at + (metres / 5.0), latitude: latitude_at(metres), longitude: 6.0, elevation: 100.0)
      end
      back = (0..(leg / 20).round).reverse_each.map do |index|
        metres = index * 20.0
        Allure::Gpx::Point.new(time: started_at + (((2 * leg) - metres) / 5.0) + 5.0, latitude: latitude_at(metres), longitude: 6.0,
                               elevation: 100.0 + gap_metres)
      end
      Allure::Gpx::Track.new(segments: [ Allure::Gpx::Segment.new(points: out + back) ])
    end

    def analyze_out_and_back(gap_metres:, elevation_filter: nil)
      Allure::Gpx::Analyzer.new(stopped_speed_threshold_km_h: 1.0, elevation_filter:)
        .analyze(out_and_back(gap_metres:)).anomalies
    end

    it "contests the ascent when the route disagrees with itself where it passes twice" do
      result = analyze_out_and_back(gap_metres: 20.0)
      finding = result["findings"].find { |entry| entry["kind"] == "elevation_mismatch" }

      expect(finding["tier"]).to eq("major")
      expect(finding["detail"]).to include("value" => 20.0, "peak" => 20.0)
      expect(result["impact"]["ascent"]).to include("gap" => 20.0)
      expect(described_class.contested_columns(result)).to eq(%w[ascent])
    end

    it "flags a small disagreement without contesting the ascent" do
      result = analyze_out_and_back(gap_metres: 12.0)
      finding = result["findings"].find { |entry| entry["kind"] == "elevation_mismatch" }

      expect(finding["tier"]).to eq("minor")
      expect(result).not_to have_key("impact")
      expect(described_class.contested_columns(result)).to eq([])
    end

    it "never checks a terrain profile against itself" do
      result = analyze_out_and_back(gap_metres: 20.0, elevation_filter: :dem)

      expect(kinds(result)).not_to include("elevation_mismatch")
    end
  end

  it "places findings in workout-cumulative distance across recording segments" do
    first = track(count: 100)
    second_times = Array.new(100) { |index| 400.0 + index }
    rates = Array.new(100) { |index| index < 40 ? nil : 140 }
    second = track(count: 100, times: second_times, heart_rates: rates)
    segments = [ Allure::Gpx::Segment.new(points: first), Allure::Gpx::Segment.new(points: second) ]

    metrics = Allure::Gpx::Analyzer.new(stopped_speed_threshold_km_h: 1.0).analyze(Allure::Gpx::Track.new(segments:))
    finding = metrics.anomalies["findings"].find { |entry| entry["kind"] == "hr_missing" }

    expect(finding["start_distance"]).to be_within(0.5).of(metrics.segments.first.distance)
    expect(finding["start_time"]).to eq(400)
  end
end
