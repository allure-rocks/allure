# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Contrast do
  it "scores black on white at 21" do
    expect(described_class.ratio("#000000", "#ffffff")).to be_within(0.01).of(21.0)
  end

  it "is order-independent" do
    expect(described_class.ratio("#0b7285", "#ffffff")).to eq(described_class.ratio("#ffffff", "#0b7285"))
  end

  it "holds white text at 4.5:1 or better on every generated-avatar hue" do
    User::AVATAR_PALETTE.each do |hex|
      expect(described_class.ratio(hex, "#ffffff")).to be >= 4.5
    end
  end

  it "holds white text on the brand primary" do
    expect(described_class.ratio(Workouts::RouteImageRenderer::TRACK_COLOUR, "#ffffff")).to be >= 4.5
  end
end
