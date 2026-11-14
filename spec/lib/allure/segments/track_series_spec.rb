# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Segments::TrackSeries do
  it "aligns one cumulative distance per coordinate, ending on the stored distance" do
    coordinates = [
      [ 6.4074, 45.0710 ],
      [ 6.4084, 45.0710 ],
      [ 6.4094, 45.0710 ]
    ]

    feature = described_class.new(coordinates:, distance: 200.0).call.fetch(:features).first

    expect(feature.dig(:geometry, :coordinates)).to eq(coordinates)
    expect(feature.dig(:properties, :segment_index)).to eq(0)
    distances = feature.dig(:properties, :distance)
    expect(distances.length).to eq(3)
    expect(distances.first).to eq(0.0)
    expect(distances.last).to eq(200.0)
    expect(distances).to eq(distances.sort)
  end

  it "stays usable when the geometry carries no length" do
    result = described_class.new(coordinates: [ [ 6.0, 45.0 ], [ 6.0, 45.0 ] ], distance: 0.0).call

    expect(result.dig(:features, 0, :properties, :distance)).to eq([ 0.0, 0.0 ])
  end
end
