# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Avatar::Crop do
  def image(width, height) = Vips::Image.black(width, height)
  def region(image, placement) = described_class.region(image:, placement:)

  let(:decoded) { image(400, 300) }

  it "scales the chosen square to the decoded image" do
    placement = { x: 400, y: 0, size: 300, width: 800, height: 600 }

    expect(region(decoded, placement)).to eq(left: 200, top: 0, size: 150)
  end

  it "accepts the string values a form sends" do
    placement = { "x" => "400", "y" => "0", "size" => "300", "width" => "800", "height" => "600" }

    expect(region(decoded, placement)).to eq(left: 200, top: 0, size: 150)
  end

  it "clamps a square that would leave the image" do
    placement = { x: -50, y: 400, size: 300, width: 800, height: 600 }

    expect(region(decoded, placement)).to eq(left: 0, top: 150, size: 150)
  end

  it "never keeps more than the short side" do
    placement = { x: 0, y: 0, size: 600, width: 800, height: 600 }

    expect(region(decoded, placement)).to eq(left: 0, top: 0, size: 300)
  end

  it "falls back to the centred square without a placement" do
    expect(region(decoded, nil)).to be_nil
    expect(region(decoded, {})).to be_nil
  end

  it "ignores a placement missing or carrying a non-numeric value" do
    expect(region(decoded, { x: 0, y: 0, size: 300, width: 800 })).to be_nil
    expect(region(decoded, { x: 0, y: 0, size: 0, width: 800, height: 600 })).to be_nil
    expect(region(decoded, { x: "nope", y: 0, size: 300, width: 800, height: 600 })).to be_nil
  end

  it "ignores a placement measured on an image with other proportions" do
    placement = { x: 0, y: 0, size: 300, width: 600, height: 800 }

    expect(region(decoded, placement)).to be_nil
  end
end
