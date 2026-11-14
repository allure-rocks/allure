# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Geometry::Projection do
  let(:started_at) { Time.utc(2026, 8, 27, 8, 0, 0) }

  it "interpolates the time at the nearest point on a polyline" do
    result = described_class.project(
      target: [ 0.005, 0.001 ],
      polyline: [ [ 0.0, 0.0 ], [ 0.01, 0.0 ] ],
      times: [ 0.0, 100.0 ]
    )

    expect(result.segment_index).to eq(0)
    expect(result.fraction).to be_within(0.0001).of(0.5)
    expect(result.time).to be_within(0.001).of(50.0)
    expect(result.distance_along_meters).to be_within(0.1).of(
      Allure::Gpx::Geo.horizontal_distance(0.0, 0.0, 0.0, 0.005)
    )
  end

  it "returns the first and last vertex boundaries" do
    polyline = [ [ 0.0, 0.0 ], [ 0.01, 0.0 ] ]
    first = described_class.project(target: polyline.first, polyline:, times: [ started_at, started_at + 100 ])
    last = described_class.project(target: polyline.last, polyline:, times: [ started_at, started_at + 100 ])

    expect(first).to have_attributes(segment_index: 0, fraction: 0.0, time: started_at)
    expect(last).to have_attributes(segment_index: 0, fraction: 1.0, time: started_at + 100)
  end

  it "chooses the earliest segment when a target is a shared vertex" do
    vertex = [ 0.005, 0.0 ]
    result = described_class.project(
      target: vertex,
      polyline: [ [ 0.0, 0.0 ], vertex, [ 0.005, 0.005 ] ],
      times: [ 0.0, 10.0, 20.0 ]
    )

    expect(result.segment_index).to eq(0)
    expect(result.fraction).to eq(1.0)
    expect(result.time).to eq(10.0)
  end
end
