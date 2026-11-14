# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workouts::RouteBasemapFetcher do
  # spec/support/route_basemap.rb stubs every fetch to nil for the rest of the
  # suite; this spec is the one that exercises the real implementation.
  before do
    allow_any_instance_of(described_class).to receive(:call).and_call_original
  end

  let(:segments) do
    [
      [ [ 6.4074, 45.0710 ], [ 6.4092, 45.0728 ], [ 6.4110, 45.0745 ] ],
      [ [ 6.4131, 45.0761 ], [ 6.4150, 45.0770 ] ]
    ]
  end
  let(:template) { "https://tiles.test/{z}/{x}/{y}.png" }
  let(:tile_bytes) do
    Vips::Image.black(256, 256).new_from_image([ 234, 231, 221 ]).write_to_buffer(".png").b
  end

  def fetch(input = segments, stub: true)
    stub_request(:get, %r{\Ahttps://tiles\.test/\d+/\d+/\d+\.png\z})
      .to_return(status: 200, body: tile_bytes, headers: { "Content-Type" => "image/png" }) if stub
    described_class.new(segments: input, raster_template: template).call
  end

  it "fetches and stitches a detailed zoom within the tile budget" do
    basemap = fetch

    expect(basemap.zoom).to be >= described_class::MAX_ZOOM - 2
    expect(basemap.png_bytes[0, 8]).to eq("\x89PNG\r\n\x1A\n".b)
    stitched = Vips::Image.new_from_buffer(basemap.png_bytes, "")
    expect(stitched.width % 256).to eq(0)
    expect(stitched.height % 256).to eq(0)
    expect((stitched.width / 256) * (stitched.height / 256)).to be <= described_class::MAX_TILES
  end

  it "stitches tiles in x/y order" do
    red = Vips::Image.black(256, 256).new_from_image([ 220, 60, 60 ]).write_to_buffer(".png").b
    blue = Vips::Image.black(256, 256).new_from_image([ 60, 90, 220 ]).write_to_buffer(".png").b
    stub_request(:get, %r{\Ahttps://tiles\.test/\d+/\d+/\d+\.png\z}).to_return do |request|
      x = request.uri.path.split("/")[2].to_i
      { status: 200, body: (x.even? ? red : blue), headers: { "Content-Type" => "image/png" } }
    end

    basemap = described_class.new(segments:, raster_template: template).call
    stitched = Vips::Image.new_from_buffer(basemap.png_bytes, "")

    # The Grenoble fixture spans several columns at the picked zoom, so the
    # red/blue checkerboard must survive stitching in tile order.
    expect(stitched.width).to be > 256
    expect(stitched.getpoint(10, 10)).not_to eq(stitched.getpoint(stitched.width - 10, 10))
  end

  it "drops to a lower zoom when the route needs more tiles than allowed" do
    points = 200.times.map { |index| [ -180.0 + index * 1.8, 0.0 + (index.even? ? 0.5 : -0.5) ] }
    basemap = fetch([ points ])

    expect(basemap).not_to be_nil
    expect(basemap.zoom).to be < described_class::MAX_ZOOM
  end

  it "falls back (nil) across the antimeridian instead of drawing wrapped tiles" do
    basemap = fetch([ [ [ 179.9, 10.0 ], [ -179.9, 10.1 ] ] ], stub: false)

    expect(basemap).to be_nil
    expect(WebMock).not_to have_requested(:get, %r{tiles\.test})
  end

  it "falls back (nil) when a tile is missing" do
    stub_request(:get, %r{\Ahttps://tiles\.test/\d+/\d+/\d+\.png\z}).to_return(status: 404)

    expect(described_class.new(segments:, raster_template: template).call).to be_nil
  end

  it "falls back (nil) when tiles time out" do
    stub_request(:get, %r{\Ahttps://tiles\.test/\d+/\d+/\d+\.png\z}).to_raise(Net::ReadTimeout)

    expect(described_class.new(segments:, raster_template: template).call).to be_nil
  end

  it "stops reading a tile response above the byte limit" do
    oversized = "x" * (described_class::MAX_TILE_BYTES + 1)
    stub_request(:get, %r{\Ahttps://tiles\.test/\d+/\d+/\d+\.png\z})
      .to_return(status: 200, body: oversized, headers: { "Content-Type" => "image/png" })

    expect(described_class.new(segments:, raster_template: template).call).to be_nil
  end

  it "rejects decoded tiles with unexpected dimensions" do
    wrong_size = Vips::Image.black(257, 256).write_to_buffer(".png").b
    stub_request(:get, %r{\Ahttps://tiles\.test/\d+/\d+/\d+\.png\z})
      .to_return(status: 200, body: wrong_size, headers: { "Content-Type" => "image/png" })

    expect(described_class.new(segments:, raster_template: template).call).to be_nil
  end

  it "rejects invalid routes like the renderer" do
    expect { fetch([]) }.to raise_error(ArgumentError)
    expect { fetch([ [ [ Float::NAN, 45.0 ], [ 6.4, 45.1 ] ] ]) }.to raise_error(ArgumentError)
  end
end
