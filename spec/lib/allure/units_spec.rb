# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Units do
  it "converts metric and imperial distances" do
    expect(described_class.metres_to_kilometres(1_500)).to eq(1.5)
    expect(described_class.metres_to_miles(1_609.344)).to eq(1.0)
    expect(described_class.metres_to_feet(0.3048)).to eq(1.0)
  end

  it "converts speeds from metres per second" do
    expect(described_class.metres_per_second_to_kilometres_per_hour(10)).to eq(36.0)
    expect(described_class.metres_per_second_to_miles_per_hour(0.44704)).to be_within(0.0001).of(1.0)
  end

  it "converts pace from seconds per kilometre to seconds per mile" do
    expect(described_class.seconds_per_kilometre_to_seconds_per_mile(300)).to be_within(0.001).of(482.8032)
  end
end
