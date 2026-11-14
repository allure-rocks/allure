# frozen_string_literal: true

require "rails_helper"

RSpec.describe Federation::RemoteMedia::Verifier do
  let(:gpx_body) { File.read(Rails.root.join("spec/fixtures/gpx/multi_segment.gpx")) }

  def png(width: 64, height: 64)
    Vips::Image.black(width, height).write_to_buffer(".png")
  end

  it "parses a valid GPX and returns the track" do
    verified = described_class.new(kind: "gpx").call(gpx_body)

    expect(verified.content_type).to eq("application/xml+gpx")
    expect(verified.track.points_count).to eq(6)
    expect(verified.track.segments.length).to eq(2)
  end

  it "parses the timestamp-less GPX Allure publishes" do
    sanitized = gpx_body.gsub(%r{<time>.*?</time>}m, "")

    verified = described_class.new(kind: "gpx").call(sanitized)

    expect(verified.track.points_count).to eq(6)
    expect(verified.track.segments.first.points.first.time).to be_nil
  end

  it "rejects malformed GPX, unknown XML, and too many points" do
    verifier = described_class.new(kind: "gpx")

    expect { verifier.call("<not-gpx/>") }
      .to raise_error(described_class::InvalidContent)
    expect { verifier.call("not xml at all") }
      .to raise_error(described_class::InvalidContent)
  end

  it "accepts a valid PNG within the pixel cap" do
    verified = described_class.new(kind: "route_image").call(png)

    expect(verified.content_type).to eq("image/png")
    expect(verified.byte_size).to eq(png.bytesize)
    expect(verified.track).to be_nil
  end

  it "rejects non-PNG bytes and oversized images" do
    verifier = described_class.new(kind: "route_image")

    expect { verifier.call("not an image") }
      .to raise_error(described_class::InvalidContent, /not a PNG/)
    expect { verifier.call(png(width: described_class::MAX_IMAGE_DIMENSION + 1, height: 1)) }
      .to raise_error(described_class::InvalidContent, /dimensions/)
  end

  it "rejects a GPX body larger than the byte cap" do
    expect { described_class.new(kind: "gpx").call("x" * (described_class::MAX_GPX_BYTES + 1)) }
      .to raise_error(described_class::InvalidContent, /too large/)
  end
end
