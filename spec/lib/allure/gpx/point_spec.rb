# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Gpx::Point do
  it "is immutable and defaults optional fields to nil" do
    point = described_class.new(time: Time.zone.now, latitude: 45.0, longitude: 6.0)

    expect(point.elevation).to be_nil
    expect(point.heart_rate).to be_nil
    expect(point.elevation?).to be(false)
    expect(point).to be_frozen
  end

  it "treats elevation 0.0 as present" do
    point = described_class.new(time: Time.zone.now, latitude: 45.0, longitude: 6.0, elevation: 0.0)
    expect(point.elevation?).to be(true)
  end
end
