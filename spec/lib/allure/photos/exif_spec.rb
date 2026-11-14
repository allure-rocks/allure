# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Photos::Exif do
  def field(value) = "#{value} (#{value}, ASCII, 1 components, 1 bytes)"

  it "reads the wall clock, the offset and a southern-western position" do
    result = described_class.parse(
      "exif-ifd2-DateTimeOriginal" => field("2026:05:01 10:20:30"),
      "exif-ifd2-OffsetTimeOriginal" => field("-03:30"),
      "exif-ifd3-GPSLatitude" => "45/1 10/1 3045/100 (45, 10, 30.45, Rational, 3 components, 24 bytes)",
      "exif-ifd3-GPSLatitudeRef" => field("S"),
      "exif-ifd3-GPSLongitude" => "5/1 46/1 12/1 ( 5, 46, 12, Rational, 3 components, 24 bytes)",
      "exif-ifd3-GPSLongitudeRef" => field("W")
    )

    expect(result.taken_at_local).to eq(Time.utc(2026, 5, 1, 10, 20, 30))
    expect(result.utc_offset).to eq(-(3 * 3600 + 30 * 60))
    expect(result.latitude).to be_within(1e-6).of(-(45 + 10 / 60.0 + 30.45 / 3600))
    expect(result.longitude).to be_within(1e-6).of(-(5 + 46 / 60.0 + 12 / 3600.0))
    expect(result).to be_position
  end

  it "falls back to the digitized time and ignores malformed values" do
    result = described_class.parse(
      "exif-ifd2-DateTimeOriginal" => field("0000:00:00 00:00:00"),
      "exif-ifd2-DateTimeDigitized" => field("2026:05:02 07:00:00"),
      "exif-ifd2-OffsetTimeOriginal" => field("+25:00"),
      "exif-ifd3-GPSLatitude" => "45/0 10/1 3/1 (bad)",
      "exif-ifd3-GPSLongitude" => "5/1 46/1 12/1 (ok)"
    )

    expect(result.taken_at_local).to eq(Time.utc(2026, 5, 2, 7))
    expect(result.utc_offset).to be_nil
    expect(result).not_to be_position
  end

  it "treats a 0/0 fix as no position" do
    result = described_class.parse(
      "exif-ifd3-GPSLatitude" => "0/1 0/1 0/1 (0)",
      "exif-ifd3-GPSLongitude" => "0/1 0/1 0/1 (0)"
    )

    expect(result).not_to be_position
    expect(result.taken_at_local).to be_nil
  end
end
