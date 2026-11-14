# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Toponyms::SampleTrack do
  SegmentValue = Data.define(:distance, :points)

  def point(distance, elevation: 100.0, latitude: 50.0, longitude: 5.0)
    { "d" => distance, "ele" => elevation, "lat" => latitude, "lon" => longitude }
  end

  it "samples a long track every 100 metres" do
    points = 1_001.times.map { |index| point(index * 100.0, elevation: index.to_f) }
    result = described_class.new(segments: [ SegmentValue.new(100_000.0, points) ]).call

    expect(result.length).to eq(1_001)
    expect(result.first).to include(distance: 0.0, role: "start")
    expect(result.last).to include(distance: 100_000.0, role: "finish")
    expect(result.map { it.fetch(:distance) }).to eq(result.map { it.fetch(:distance) }.sort)
  end

  it "keeps both endpoints on a very long track without a sampling cap" do
    points = 301.times.map { |index| point(index * 1_000.0) }

    result = described_class.new(segments: [ SegmentValue.new(300_000.0, points) ]).call

    expect(result.length).to eq(301)
    expect(result.first).to include(distance: 0.0, role: "start")
    expect(result.last).to include(distance: 300_000.0, role: "finish")
  end

  it "adds a high point between ordinary distance samples" do
    points = 31.times.map do |index|
      point(index * 100.0, elevation: index == 15 ? 500.0 : 100.0)
    end

    result = described_class.new(segments: [ SegmentValue.new(3_000.0, points) ]).call

    expect(result).to include(a_hash_including(distance: 1_500.0, elevation: 500.0, role: "high_point"))
  end

  it "uses workout-cumulative distance across recording segments" do
    segments = [
      SegmentValue.new(1_000.0, [ point(0), point(1_000) ]),
      SegmentValue.new(1_000.0, [ point(0), point(1_000) ])
    ]

    result = described_class.new(segments:).call

    expect(result.last).to include(distance: 2_000.0, role: "finish")
  end

  it "keeps recording segment boundaries in addition to regular samples" do
    segments = [
      SegmentValue.new(550.0, [ point(0), point(550) ]),
      SegmentValue.new(550.0, [ point(0), point(550) ])
    ]

    result = described_class.new(segments:).call

    expect(result).to include(a_hash_including(distance: 550.0, role: "segment_boundary"))
  end

  it "continues sampling when segment metrics round below the prior point" do
    segments = [
      SegmentValue.new(5_000.0, [ point(0), point(5_000.1) ]),
      SegmentValue.new(5_000.0, [ point(0), point(2_000.0), point(5_000.0) ])
    ]

    result = described_class.new(segments:).call

    expect(result).to include(a_hash_including(distance: 7_000.0))
  end

  it "ignores malformed points and returns empty for an empty track" do
    malformed = SegmentValue.new(0, [ { "d" => 0, "lat" => nil, "lon" => 5.0 } ])

    expect(described_class.new(segments: [ malformed ]).call).to eq([])
    expect(described_class.new(segments: []).call).to eq([])
  end
end
