# frozen_string_literal: true

require "rails_helper"
require "digest"
require "vips"

RSpec.describe Workouts::RouteImageRenderer do
  let(:segments) do
    [
      [ [ 6.4074, 45.0710 ], [ 6.4092, 45.0728 ], [ 6.4110, 45.0745 ] ],
      [ [ 6.4131, 45.0761 ], [ 6.4150, 45.0770 ] ]
    ]
  end

  def render(input = segments)
    described_class.new(segments: input, line_colour: "#206bc4").call
  end

  # Reads the pixels once: tens of thousands of `getpoint` calls each build a
  # libvips pipeline whose native objects wait for Ruby's GC, which a large
  # Rails heap runs rarely, so the scan slowed down to several minutes.
  def each_sampled_pixel(image, step)
    image = image.cast(:uchar)
    bytes = image.write_to_memory
    (0...image.width).step(step) do |x|
      (0...image.height).step(step) do |y|
        offset = ((y * image.width) + x) * image.bands
        yield bytes.getbyte(offset), bytes.getbyte(offset + 1), bytes.getbyte(offset + 2)
      end
    end
  end

  it "renders a deterministic 800 by 450 PNG" do
    first = render
    second = render
    first_image = Vips::Image.new_from_file(first.path)

    expect(first.read(8)).to eq("\x89PNG\r\n\x1A\n".b)
    expect([ first_image.width, first_image.height ]).to eq([ 800, 450 ])
    expect(Digest::SHA256.file(first.path).hexdigest).to eq(Digest::SHA256.file(second.path).hexdigest)
  ensure
    first&.close!
    second&.close!
  end

  it "unblocks the SVG loader only for its own conversion" do
    svg = %(<svg xmlns="http://www.w3.org/2000/svg" width="4" height="4"><rect width="4" height="4"/></svg>)
    output = render

    expect(output.read(8)).to eq("\x89PNG\r\n\x1A\n".b)
    expect { Vips::Image.new_from_buffer(svg, "").avg }.to raise_error(Vips::Error)
  ensure
    output&.close!
  end

  it "handles antimeridian, vertical, horizontal, and duplicate-point routes" do
    inputs = [
      [ [ [ 179.9, 10.0 ], [ -179.9, 10.1 ] ] ],
      [ [ [ 6.4, 45.0 ], [ 6.4, 45.1 ] ] ],
      [ [ [ 6.4, 45.0 ], [ 6.5, 45.0 ] ] ],
      [ [ [ 6.4, 45.0 ], [ 6.4, 45.0 ] ] ]
    ]

    inputs.each do |input|
      output = render(input)
      image = Vips::Image.new_from_file(output.path)
      expect([ image.width, image.height ]).to eq([ 800, 450 ])
      output.close!
    end
  end

  it "bounds a large route without recursive stack growth or dropped endpoints" do
    points = 10_000.times.map do |index|
      [ 6.0 + (index * 0.00001), 45.0 + (Math.sin(index / 25.0) * 0.001) ]
    end

    output = render([ points ])
    expect(Vips::Image.new_from_file(output.path).width).to eq(800)
  ensure
    output&.close!
  end

  it "omits arrows when fewer than three remain after deduplication" do
    # Three recorded passes produce six candidate arrows, but only two
    # remain after deduplication on this fitted horizontal route.
    output = render(Array.new(3) { [ [ 6.4, 45.0 ], [ 6.5, 45.0 ] ] })
    image = Vips::Image.new_from_file(output.path)

    # A horizontal route fills the padded canvas (x 32..768 at y 225), so the
    # first slot centre would sit at 192, with its shaft at y 237. Both
    # that position and the gap retain the canvas background.
    shaft = image.getpoint(192, 237)
    gap = image.getpoint(192, 233)
    expect(shaft[0..2]).to eq([ 244.0, 246.0, 250.0 ])
    expect(gap[0..2]).to eq([ 244.0, 246.0, 250.0 ])
  ensure
    output&.close!
  end

  it "draws three arrows even when each belongs to a different recording segment" do
    output = render([
      [ [ 6.4, 45.0 ], [ 6.42, 45.0 ] ],
      [ [ 6.44, 44.99 ], [ 6.46, 44.99 ] ],
      [ [ 6.48, 44.98 ], [ 6.5, 44.98 ] ]
    ])
    image = Vips::Image.new_from_file(output.path)
    # Each recording segment is short enough for a single arrow. The
    # middle segment is centred at (400, 225), with its shaft 12 px below.
    shaft = image.getpoint(400, 237)
    expect(shaft[0]).to be < 120
    expect(shaft[2]).to be > 180
  ensure
    output&.close!
  end

  it "renders a smoothed route and rejects an unknown smoothing level" do
    zigzag = Array.new(9) { |index| [ 6.4 + (index * 0.0002), 45.0 + (index.odd? ? 0.00008 : -0.00008) ] }
    output = described_class.new(segments: [ zigzag ], line_colour: "#206bc4", smoothing: "medium").call

    expect(Vips::Image.new_from_file(output.path).width).to eq(800)
    expect do
      described_class.new(segments:, line_colour: "#206bc4", smoothing: "extreme")
    end.to raise_error(ArgumentError, "invalid smoothing level")
  ensure
    output&.close!
  end

  it "renders the dark variant on the dark surface and rejects an unknown theme" do
    output = described_class.new(segments:, line_colour: "#206bc4", theme: "dark").call
    image = Vips::Image.new_from_file(output.path)

    corner = image.getpoint(4, 4)
    expect(corner[0..2]).to eq([ 23.0, 23.0, 23.0 ])
    expect do
      described_class.new(segments:, line_colour: "#206bc4", theme: "sepia")
    end.to raise_error(ArgumentError, "invalid route image theme")
  ensure
    output&.close!
  end

  it "paints a virtual world's colour and credit instead of the application surface" do
    output = described_class.new(
      segments:, line_colour: "#206bc4", background: "#0884e2", attribution: "© Zwift"
    ).call
    image = Vips::Image.new_from_file(output.path)

    expect(image.getpoint(4, 4)[0..2]).to eq([ 8.0, 132.0, 226.0 ])
    expect(described_class.new(segments:, line_colour: "#206bc4", attribution: "© Zwift")
      .send(:attribution_text)).to include("© Zwift")
    expect(described_class.new(segments:, line_colour: "#206bc4").send(:attribution_text))
      .to include("OpenStreetMap")
    expect do
      described_class.new(segments:, line_colour: "#206bc4", background: "blue")
    end.to raise_error(ArgumentError, "invalid route image background")
  ensure
    output&.close!
  end

  it "draws a clockwise loop's arrows outside rather than inside the route" do
    clockwise = [ [ 6.4, 45.0 ], [ 6.41, 45.0 ], [ 6.41, 44.99 ], [ 6.4, 44.99 ], [ 6.4, 45.0 ] ]
    output = render([ clockwise ])
    image = Vips::Image.new_from_file(output.path)

    # The top edge travels east at y 32: its exterior is above it, at y 20.
    # The first arrow shaft is near x 424 after the route is fitted.
    exterior = image.getpoint(424, 20)
    interior = image.getpoint(424, 44)
    expect(exterior[0]).to be < 120
    expect(exterior[2]).to be > 180
    expect(interior[0..2]).to eq([ 244.0, 246.0, 250.0 ])
  ensure
    output&.close!
  end

  it "rejects invalid routes and colours" do
    expect { render([]) }.to raise_error(ArgumentError)
    expect { render([ [ [ Float::NAN, 45.0 ], [ 6.4, 45.1 ] ] ]) }.to raise_error(ArgumentError)
    expect do
      described_class.new(segments:, line_colour: "red")
    end.to raise_error(ArgumentError, "invalid line colour")
  end

  it "marks the finish with a checkered flag and keeps the brand track colour in sync" do
    expect(described_class::TRACK_COLOUR).to eq("#c5426c")
    scss = Rails.root.join("app/frontend/styles/_brand.scss").read
    expect(scss).to include("$primary: #{described_class::TRACK_COLOUR};")

    output = render
    image = Vips::Image.new_from_file(output.path)
    dark = 0
    white = 0
    each_sampled_pixel(image, 3) do |r, g, b|
      dark += 1 if r < 60 && g < 60 && b < 60
      white += 1 if r > 250 && g > 250 && b > 250
    end

    expect(dark).to be_positive
    expect(white).to be_positive
  ensure
    output&.close!
  end

  context "with a basemap" do
    let(:zoom) { 14 }
    let(:tile_bytes) do
      Vips::Image.black(256, 256).new_from_image([ 234, 231, 221 ]).write_to_buffer(".png").b
    end
    let(:basemap) do
      gx = Workouts::RouteBasemapFetcher.longitude_to_global_x(6.41, zoom)
      gy = Workouts::RouteBasemapFetcher.latitude_to_global_y(45.073, zoom)
      Workouts::RouteBasemapFetcher::Basemap.new(tile_bytes, zoom, (gx / 256).floor, (gy / 256).floor)
    end

    def render_with_basemap(input = segments, map = basemap)
      described_class.new(segments: input, line_colour: "#206bc4", basemap: map).call
    end

    it "renders an 800 by 450 PNG over the raster background" do
      output = render_with_basemap
      image = Vips::Image.new_from_file(output.path)

      expect(output.read(8)).to eq("\x89PNG\r\n\x1A\n".b)
      expect([ image.width, image.height ]).to eq([ 800, 450 ])

      beige = 0
      blue = 0
      each_sampled_pixel(image, 7) do |r, g, b|
        beige += 1 if (r - 234).abs < 12 && (g - 231).abs < 12 && (b - 221).abs < 12
        blue += 1 if b > 150 && r < 100 && g < 150
      end
      expect(beige).to be_positive
      expect(blue).to be_positive
    ensure
      output&.close!
    end

    it "differs from the tile-less rendering and stays deterministic" do
      with_basemap = render_with_basemap
      without = render
      second = render_with_basemap
      with_basemap.rewind
      without.rewind

      expect(with_basemap.read).not_to eq(without.read)
      expect(Digest::SHA256.file(with_basemap.path).hexdigest)
        .to eq(Digest::SHA256.file(second.path).hexdigest)
    ensure
      with_basemap&.close!
      without&.close!
      second&.close!
    end

    it "rejects a corrupt basemap instead of attaching a broken image" do
      bad = Workouts::RouteBasemapFetcher::Basemap.new("not a png".b, zoom, 0, 0)

      expect { render_with_basemap(segments, bad) }
        .to raise_error(Workouts::RouteImageRenderer::RenderingError)
    end
  end
end
