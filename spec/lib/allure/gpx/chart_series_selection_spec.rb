# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Gpx::ChartSeries do
  it "optionally keeps original point indexes for owner selection" do
    started_at = Time.zone.parse("2026-08-28 08:00:00")
    segment = instance_double(
      TrackSegment,
      started_at: started_at,
      points: [
        { "t" => 0, "d" => 0.0, "lat" => 45.0, "lon" => 6.4, "ele" => 100.0 },
        { "t" => 60, "d" => 100.0, "lat" => 45.0, "lon" => 6.401, "ele" => 101.0 }
      ],
      distance: 100.0
    )

    points = described_class.new(
      workout_started_at: started_at,
      segments: [ segment ],
      include_index: true
    ).call

    expect(points).to include(
      { distance: 0.0, elapsed_time: 0, elevation: 100.0, index: 0, segment_index: 0 },
      { distance: 100.0, elapsed_time: 60, elevation: 101.0, index: 1, segment_index: 0 }
    )
  end
end
