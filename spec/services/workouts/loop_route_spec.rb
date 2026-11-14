# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workouts::LoopRoute do
  def route(workout, first:, last:)
    create(
      :track_segment,
      workout:,
      points: [
        { "t" => 0, "d" => 0.0, "lat" => first[0], "lon" => first[1], "ele" => 100.0 },
        { "t" => 600, "d" => 5_000.0, "lat" => last[0], "lon" => last[1], "ele" => 100.0 }
      ],
      points_count: 2
    )
  end

  it "accepts a route whose endpoints sit within 250 metres" do
    workout = create(:workout)
    route(workout, first: [ 45.0, 6.0 ], last: [ 45.0005, 6.0 ])

    expect(described_class.new(workout:).call).to be(true)
  end

  it "rejects a route whose endpoints are far apart" do
    workout = create(:workout)
    route(workout, first: [ 45.0, 6.0 ], last: [ 45.1, 6.0 ])

    expect(described_class.new(workout:).call).to be(false)
  end

  it "is false without usable points" do
    workout = create(:workout)

    expect(described_class.new(workout:).call).to be(false)
  end

  it "is false when a point lacks finite coordinates" do
    workout = create(:workout)
    segment = instance_double(
      TrackSegment,
      points: [ { "lat" => 45.0, "lon" => 6.0 }, { "lat" => nil, "lon" => 6.0 } ]
    )
    allow(workout).to receive(:track_segments).and_return([ segment ])

    expect(described_class.new(workout:).call).to be(false)
  end
end
