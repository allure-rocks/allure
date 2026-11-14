# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Segments::PointStream do
  StreamSegment = Data.define(:position, :started_at, :distance, :points)

  let(:started_at) { Time.utc(2026, 8, 27, 8, 0, 0) }

  it "orders recording segments and preserves their time and distance gaps" do
    segments = [
      stream_segment(
        position: 1,
        started_at: started_at + 30,
        distance: 50.0,
        points: [ point(0, 0.0, 2.0), point(5, 50.0, 2.001) ]
      ),
      stream_segment(
        position: 0,
        started_at:,
        distance: 100.0,
        points: [ point(0, 0.0, 0.0), point(10, 100.0, 0.001) ]
      )
    ]

    result = described_class.new(segments:, workout_started_at: started_at).call

    expect(result.map(&:index)).to eq([ 0, 1, 2, 3 ])
    expect(result.map(&:segment_index)).to eq([ 0, 0, 1, 1 ])
    expect(result.map(&:distance)).to eq([ 0.0, 100.0, 100.0, 150.0 ])
    expect(result.map(&:elapsed_time)).to eq([ 0, 10, 30, 35 ])
    expect(result.map(&:time)).to eq([ started_at, started_at + 10, started_at + 30, started_at + 35 ])
  end

  private

  def stream_segment(position:, started_at:, distance:, points:)
    StreamSegment.new(position:, started_at:, distance:, points:)
  end

  def point(time, distance, longitude)
    {
      "t" => time,
      "d" => distance,
      "lat" => 45.0,
      "lon" => longitude,
      "ele" => 100.0,
      "v" => 5.0,
      "hr" => 140,
      "cad" => 80,
      "pw" => 200
    }
  end
end
