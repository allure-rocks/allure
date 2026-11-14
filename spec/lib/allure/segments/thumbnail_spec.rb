# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Segments::Thumbnail do
  it "fits the course into the square, keeping its aspect ratio, north up" do
    path = described_class.new([ [ 0.0, 0.0 ], [ 0.0, 1.0 ] ], size: 10, padding: 0).call

    expect(path).to eq("M5.0 10.0 L5.0 0.0")
  end

  it "scales longitudes by the cosine of the latitude" do
    coordinates = [ [ 0.0, 59.5 ], [ 2.0, 59.5 ], [ 2.0, 60.5 ], [ 0.0, 60.5 ] ]

    path = described_class.new(coordinates, size: 10, padding: 0).call

    # At 60° a degree of longitude spans half a degree of latitude: the box is
    # as wide as it is tall.
    expect(path).to eq("M0.0 10.0 L10.0 10.0 L10.0 0.0 L0.0 0.0")
  end

  it "draws nothing for a degenerate or missing line" do
    expect(described_class.new(nil, size: 10).call).to be_nil
    expect(described_class.new([ [ 1.0, 1.0 ] ], size: 10).call).to be_nil
    expect(described_class.new([ [ 1.0, 1.0 ], [ 1.0, 1.0 ] ], size: 10).call).to be_nil
  end
end
