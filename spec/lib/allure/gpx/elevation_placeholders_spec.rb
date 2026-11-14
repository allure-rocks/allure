# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Gpx::ElevationPlaceholders do
  def point(elevation)
    Allure::Gpx::Point.new(
      time: Time.utc(2026, 6, 1, 8, 0, 0),
      latitude: 45.0,
      longitude: 6.4,
      elevation:
    )
  end

  it "keeps exact zeros on a fully recorded profile" do
    points = [ point(0.0), point(0.0), point(0.0) ]

    expect(described_class.resolve(points)).to eq(points)
  end

  it "turns exact zeros into missing values on a partially recorded profile" do
    points = [ point(nil), point(0.0), point(120.0) ]

    expect(described_class.resolve(points).map(&:elevation)).to eq([ nil, nil, 120.0 ])
  end

  it "keeps a partial profile that has no exact zero" do
    points = [ point(nil), point(120.0) ]

    expect(described_class.resolve(points)).to eq(points)
  end

  it "keeps every other point field untouched" do
    original = point(0.0)
    resolved = described_class.resolve([ point(nil), original ])

    expect(resolved.last).to have_attributes(
      time: original.time,
      latitude: original.latitude,
      longitude: original.longitude,
      heart_rate: nil,
      cadence: nil,
      power: nil
    )
  end
end
