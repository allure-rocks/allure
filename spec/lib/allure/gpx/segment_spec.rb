# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Gpx::Segment do
  def point(offset_seconds) = Allure::Gpx::Point.new(time: Time.zone.now + offset_seconds, latitude: 45.0, longitude: 6.0)

  it "freezes its points and exposes first/last/size" do
    points = [ point(0), point(60) ]
    segment = described_class.new(points:)

    expect(segment.points).to be_frozen
    expect(segment.size).to eq(2)
    expect(segment.first_point).to eq(points.first)
    expect(segment.last_point).to eq(points.last)
  end
end
