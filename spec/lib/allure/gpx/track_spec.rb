# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Gpx::Track do
  include ActiveSupport::Testing::TimeHelpers

  def point(offset_seconds) = Allure::Gpx::Point.new(time: Time.zone.now + offset_seconds, latitude: 45.0, longitude: 6.0)

  it "defaults optional attributes and sums points across segments" do
    segments = [
      Allure::Gpx::Segment.new(points: [ point(0), point(60) ]),
      Allure::Gpx::Segment.new(points: [ point(120), point(180), point(240) ])
    ]
    track = described_class.new(segments:)

    expect(track.creator).to be_nil
    expect(track.name).to be_nil
    expect(track.calories).to be_nil
    expect(track.source_max_speed).to be_nil
    expect(track.source_ascent).to be_nil
    expect(track.source_descent).to be_nil
    expect(track.points_count).to eq(5)
    expect(track.segments).to be_frozen
    expect(track.laps).to be_empty
  end

  it "retains source-reported maximum speed" do
    track = described_class.new(
      segments: [ Allure::Gpx::Segment.new(points: [ point(0), point(60) ]) ],
      source_max_speed: 17.25
    )

    expect(track.source_max_speed).to eq(17.25)
  end

  it "retains source-reported elevation totals" do
    track = described_class.new(
      segments: [ Allure::Gpx::Segment.new(points: [ point(0), point(60) ]) ],
      source_ascent: 123.0,
      source_descent: 45.0
    )

    expect(track.source_ascent).to eq(123.0)
    expect(track.source_descent).to eq(45.0)
  end

  it "freezes a provided laps list" do
    lap = Allure::Gpx::Lap.new(
      number: 1, started_at: Time.zone.now, elapsed_time: 90, moving_time: 80, distance: 405.0
    )
    track = described_class.new(segments: [ Allure::Gpx::Segment.new(points: [ point(0), point(60) ]) ], laps: [ lap ])

    expect(track.laps).to contain_exactly(lap)
    expect(track.laps).to be_frozen
  end

  it "clips the text a file hands on, leaving short and missing values alone (docs/dev/WORKOUT.md)" do
    track = described_class.new(creator: "c" * 300, name: "n" * 300, description: "d" * 10_001, segments: [])
    lap = Allure::Gpx::Lap.new(number: 1, started_at: Time.utc(2026, 6, 1), elapsed_time: 60, moving_time: 60,
                               lap_trigger: "t" * 40)

    expect(track).to have_attributes(creator: "c" * 255, name: "n" * 255, description: "d" * 10_000)
    expect(lap.lap_trigger).to eq("t" * 32)
    expect(described_class.new(creator: "Garmin", segments: [])).to have_attributes(creator: "Garmin", name: nil)
  end

  describe "#shifted (docs/dev/DEMO.md)" do
    let(:start) { Time.zone.parse("2026-04-19 08:00:00") }
    let(:track) do
      described_class.new(
        creator: "Garmin",
        segments: [ Allure::Gpx::Segment.new(points: [ point(0), point(60), point(120) ]) ],
        laps: [ Allure::Gpx::Lap.new(number: 1, started_at: start, elapsed_time: 120, moving_time: 110,
                                     distance: 800.0, lap_trigger: "manual") ]
      )
    end

    around { |example| travel_to(start) { example.run } }

    it "moves every point time and lap start by the offset, leaving the rest alone" do
      shifted = track.shifted(86_400 * 195)

      expect(shifted).not_to equal(track)
      expect(shifted.segments).to be_frozen
      expect(shifted.laps).to be_frozen
      expect(shifted.creator).to eq("Garmin")
      expect(shifted.segments.first.points.map(&:time))
        .to eq([ start + 86_400 * 195, start + 60 + 86_400 * 195, start + 120 + 86_400 * 195 ])
      expect(shifted.laps.first.started_at).to eq(start + 86_400 * 195)
      expect(shifted.laps.first).to have_attributes(elapsed_time: 120, moving_time: 110, distance: 800.0, lap_trigger: "manual")
      expect(shifted.segments.first.points).to all(have_attributes(latitude: 45.0, longitude: 6.0))
    end

    it "keeps the source track untouched and answers it unchanged for a zero or nil offset" do
      before_points = track.segments.first.points.map(&:time)

      expect(track.shifted(0)).to equal(track)
      expect(track.shifted(nil)).to equal(track)
      track.shifted(60)
      expect(track.segments.first.points.map(&:time)).to eq(before_points)
    end
  end
end
