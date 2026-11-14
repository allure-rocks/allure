# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Gpx::ElevationConsistency do
  STEP = described_class::SAMPLE_METRES

  def sample(distance:, time:, elevation:, latitude:, longitude:, segment: 0)
    described_class::Sample.new(distance:, time:, elevation:, latitude:, longitude:, segment:)
  end

  def latitude_at(metres) = 45.0 + (metres / 111_320.0)

  # A straight out-and-back: the same road ridden out and back, the return
  # reading `gap_metres` higher and standing `offset_metres` to the side. A
  # `drift` adds that many metres per metre to the return's reading, the way
  # a second path along the same slope reads the terrain itself.
  def out_and_back(gap_metres:, leg: 3_000.0, speed: 5.0, offset_metres: 0.0, segments: 1, drift: 0.0)
    samples = []
    longitude = 6.0
    offset = offset_metres / (111_320.0 * Math.cos(45.0 * Math::PI / 180.0))
    (0..(leg / STEP).round).each do |index|
      distance = index * STEP
      samples << sample(distance:, time: distance / speed, elevation: 100.0,
                        latitude: latitude_at(distance), longitude: longitude)
    end
    (0..(leg / STEP).round).reverse_each do |index|
      distance = index * STEP
      samples << sample(distance: (2 * leg) - distance, time: ((2 * leg) - distance) / speed + 5.0,
                        elevation: 100.0 + gap_metres + (drift * distance), latitude: latitude_at(distance),
                        longitude: longitude + offset, segment: segments - 1)
    end
    samples
  end

  # A north road of `leg` metres and, `pause` seconds later, an east-west road
  # crossing it at the same point `gap_metres` higher.
  def crossing(gap_metres:, leg: 3_000.0, speed: 5.0)
    samples = []
    (0..(leg / STEP).round).each do |index|
      distance = index * STEP
      samples << sample(distance:, time: distance / speed, elevation: 100.0,
                        latitude: latitude_at(distance), longitude: 6.0)
    end
    crossing_latitude = latitude_at(leg / 2.0)
    start_time = (leg / speed) + 400.0
    (0..100).each do |index|
      metres = index * STEP
      samples << sample(distance: leg + metres, time: start_time + (metres / speed), elevation: 100.0 + gap_metres,
                        latitude: crossing_latitude, longitude: 6.0 - (metres / (111_320.0 * Math.cos(45.0 * Math::PI / 180.0))),
                        segment: 1)
    end
    samples
  end

  it "reports the gap between two passages of one road, across recording segments" do
    findings = described_class.findings(out_and_back(gap_metres: 20.0, segments: 2))

    expect(findings.length).to eq(1)
    finding = findings.first
    expect(finding["kind"]).to eq("elevation_mismatch")
    expect(finding["detail"]).to include("value" => 20.0, "metres" => 20.0, "peak" => 20.0)
    # The pairing only starts where the two passages are 300 s apart, and the
    # finding places on the second passage, the one that disagrees.
    expect(finding["detail"]["first_distance"]).to be_within(STEP).of(2_250.0)
    expect(finding["detail"]["first_time"]).to be_within(5).of(450)
    expect(finding["start_distance"]).to be_within(STEP * 1.5).of(3_750.0)
    expect(finding["end_distance"]).to be_within(STEP * 1.5).of(6_000.0)
  end

  it "accepts the two passages the other way round, as an out-and-back meets them" do
    findings = described_class.findings(out_and_back(gap_metres: -18.0))

    expect(findings.length).to eq(1)
    expect(findings.first["detail"]["value"]).to eq(-18.0)
  end

  it "reports nothing when the two passages agree" do
    expect(described_class.findings(out_and_back(gap_metres: 0.0))).to eq([])
  end

  it "leaves a gap under the threshold alone" do
    expect(described_class.findings(out_and_back(gap_metres: 6.0))).to eq([])
  end

  it "leaves a road that only crosses overhead alone" do
    expect(described_class.findings(crossing(gap_metres: 20.0))).to eq([])
  end

  it "leaves a second path along the same slope alone, its gap reading the terrain" do
    expect(described_class.findings(out_and_back(gap_metres: 20.0, drift: 0.02))).to eq([])
  end

  it "keeps a stretch whose gap drifts gently" do
    findings = described_class.findings(out_and_back(gap_metres: 20.0, drift: 0.005))

    expect(findings.length).to eq(1)
    expect(findings.first["detail"]["value"]).to be_between(20.0, 32.0)
  end

  it "leaves a tight out-and-back alone, its passages too close in time" do
    expect(described_class.findings(out_and_back(gap_metres: 20.0, leg: 250.0))).to eq([])
  end

  it "leaves a stretch shorter than the minimum alone" do
    # Two parallel roads 330 m apart joined by a 120 m stretch of shared
    # ground: the disagreement is real but too short to read as a drift.
    samples = []
    latitude = 45.0
    (0..(1_500 / STEP).round).each do |index|
      distance = index * STEP
      samples << sample(distance:, time: distance / 5.0, elevation: 100.0, latitude: latitude_at(distance), longitude: 6.0)
    end
    start_time = 400.0
    samples << sample(distance: 1_500.0, time: start_time, elevation: 100.0, latitude: latitude_at(1_200.0), longitude: 6.0,
                      segment: 1)
    (1..(600 / STEP).round).each do |index|
      metres = index * STEP
      samples << sample(distance: 1_500.0 + metres, time: start_time + (metres / 5.0), elevation: 100.0 + 20.0,
                        latitude: latitude_at(1_200.0 + metres), longitude: 6.0, segment: 1)
    end
    (1..(120 / STEP).round).each do |index|
      metres = index * STEP
      samples << sample(distance: 2_100.0 + metres, time: start_time + 120.0 + (metres / 5.0), elevation: 130.0,
                        latitude: latitude_at(1_800.0), longitude: 6.0 + (metres / 111_320.0), segment: 1)
    end

    expect(described_class.findings(samples)).to eq([])
  end

  it "reports nothing for a recording without a second passage" do
    samples = (0..150).map do |index|
      distance = index * STEP
      sample(distance:, time: distance / 5.0, elevation: 100.0, latitude: latitude_at(distance), longitude: 6.0)
    end

    expect(described_class.findings(samples)).to eq([])
  end

  describe "a recording that keeps returning to the same ground" do
    # `laps` turns of a circle of `circumference` metres, one sample every
    # `STEP` metres, the reading raised by `offset` from lap `offset_from`.
    # A `jitter` moves each position by up to that many metres, the way GPS
    # noise keeps two passages from ever standing at exactly the same point.
    def laps(count, circumference:, speed:, offset: 0.0, offset_from: nil, jitter: 0.0)
      random = Random.new(20_261_024)
      radius = circumference / (2 * Math::PI)
      metres_per_longitude = 111_320.0 * Math.cos(45.0 * Math::PI / 180.0)
      (0...((count * circumference) / STEP).round).map do |index|
        distance = index * STEP
        angle = distance / radius
        lap = (distance / circumference).floor
        elevation = offset_from && lap >= offset_from ? 100.0 + offset : 100.0
        north = (radius * Math.sin(angle)) + random.rand(-jitter..jitter)
        east = (radius * (1 - Math.cos(angle))) + random.rand(-jitter..jitter)
        sample(distance:, time: distance / speed, elevation:,
               latitude: latitude_at(north), longitude: 6.0 + (east / metres_per_longitude))
      end
    end

    # The pairing before candidates were capped: every earlier sample of the
    # neighbouring cells.
    def uncapped_pairs(points)
      directions = described_class.headings(points)
      grid = Hash.new { |hash, key| hash[key] = [] }
      points.each_index.filter_map do |b_index|
        cell = described_class.cell(points[b_index])
        best = nil
        (-1..1).each do |row|
          (-1..1).each do |column|
            grid[[ cell[0] + row, cell[1] + column ]].each do |a_index|
              candidate = described_class.pair(points, directions, a_index, b_index)
              next unless candidate
              next if best && best[:distance] <= candidate[:distance]

              best = candidate
            end
          end
        end
        grid[cell] << b_index
        best
      end
    end

    it "pairs exactly as before while each cell holds few passages" do
      [ out_and_back(gap_metres: 20.0, segments: 2), laps(8, circumference: 400.0, speed: 5.0, jitter: 3.0) ].each do |samples|
        points = described_class.resample(samples)
        pairs = described_class.pairs(points, described_class.headings(points))

        expect(pairs).not_to be_empty
        expect(pairs).to eq(uncapped_pairs(points))
      end
    end

    it "still reports a re-zeroed barometer on a track ridden for many laps" do
      findings = described_class.findings(laps(40, circumference: 400.0, speed: 5.0, offset: 20.0, offset_from: 20))

      expect(findings).not_to be_empty
      expect(findings.map { |finding| finding["detail"]["value"] }).to all(eq(20.0))
    end

    it "compares each sample with a bounded number of earlier passages" do
      samples = laps(2_200, circumference: 94.0, speed: 10.0)
      points = described_class.resample(samples)
      calls = 0
      allow(Allure::Gpx::Geo).to receive(:horizontal_distance).and_wrap_original do |original, *arguments|
        calls += 1
        original.call(*arguments)
      end

      expect(described_class.findings(samples)).to eq([])
      expect(points.length).to be > 10_000
      expect(calls).to be <= 9 * described_class::CELL_CANDIDATES * points.length
    end
  end
end
