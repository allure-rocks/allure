# frozen_string_literal: true

require "rails_helper"
require "tmpdir"
require "vips"

RSpec.describe Workouts::MaplibreRouteImageRenderer do
  let(:segments) { [ [ [ 6.4074, 45.0710 ], [ 6.4110, 45.0745 ] ] ] }
  let(:fixture) { Tempfile.new([ "route-fixture", ".png" ], binmode: true) }
  let(:runner) { Tempfile.new([ "fake-route-renderer", ".mjs" ], binmode: true) }

  before do
    Vips::Image.black(1_600, 900).pngsave(fixture.path)
  end

  after do
    fixture.close!
    runner.close!
  end

  def renderer
    described_class.new(
      segments:,
      line_colour: "#206bc4",
      style_url: "https://tiles.example.test/style.json",
      runner_path: runner.path,
      process_environment: { "FAKE_ROUTE_IMAGE" => fixture.path }
    )
  end

  it "returns a validated 1600 by 900 PNG from the isolated renderer process" do
    runner.write(<<~JAVASCRIPT)
      import fs from "node:fs";
      JSON.parse(fs.readFileSync(0, "utf8"));
      fs.copyFileSync(process.env.FAKE_ROUTE_IMAGE, process.argv.at(-1));
    JAVASCRIPT
    runner.flush

    output = renderer.call
    image = Vips::Image.new_from_file(output.path)

    expect([ image.width, image.height ]).to eq([ 1_600, 900 ])
    expect(output.read(8)).to eq("\x89PNG\r\n\x1A\n".b)
  ensure
    output&.close!
  end

  it "raises a rendering error with bounded process diagnostics" do
    runner.write("process.stderr.write('browser failed'); process.exit(2);\n")
    runner.flush

    expect { renderer.call }
      .to raise_error(described_class::RenderingError, /browser failed/)
  end

  it "rejects a PNG with unexpected dimensions" do
    Vips::Image.black(800, 450).pngsave(fixture.path)
    runner.write(<<~JAVASCRIPT)
      import fs from "node:fs";
      fs.readFileSync(0, "utf8");
      fs.copyFileSync(process.env.FAKE_ROUTE_IMAGE, process.argv.at(-1));
    JAVASCRIPT
    runner.flush

    expect { renderer.call }
      .to raise_error(described_class::RenderingError, /expected 1600x900/)
  end

  it "validates the bounded render timeout before starting a process" do
    expect do
      described_class.new(segments:, line_colour: "#206bc4", timeout_ms: 999)
    end.to raise_error(ArgumentError, "invalid route image render timeout")
  end

  it "carries the display smoothing level in the renderer payload" do
    captured = Tempfile.new("route-payload", binmode: true)
    runner.write(<<~JAVASCRIPT)
      import fs from "node:fs";
      fs.writeFileSync(process.env.CAPTURED_PAYLOAD, fs.readFileSync(0));
      fs.copyFileSync(process.env.FAKE_ROUTE_IMAGE, process.argv.at(-1));
    JAVASCRIPT
    runner.flush

    output = described_class.new(
      segments:,
      line_colour: "#206bc4",
      smoothing: "medium",
      style_url: "https://tiles.example.test/style.json",
      runner_path: runner.path,
      process_environment: { "FAKE_ROUTE_IMAGE" => fixture.path, "CAPTURED_PAYLOAD" => captured.path }
    ).call

    expect(JSON.parse(captured.read)).to include("smoothing" => "medium")
  ensure
    output&.close!
    captured&.close!
  end

  it "rejects an unknown smoothing level before starting a process" do
    expect do
      described_class.new(segments:, line_colour: "#206bc4", smoothing: "extreme")
    end.to raise_error(ArgumentError, "invalid smoothing level")
  end

  it "carries the image theme in the renderer payload and rejects an unknown one" do
    captured = Tempfile.new("route-payload", binmode: true)
    runner.write(<<~JAVASCRIPT)
      import fs from "node:fs";
      fs.writeFileSync(process.env.CAPTURED_PAYLOAD, fs.readFileSync(0));
      fs.copyFileSync(process.env.FAKE_ROUTE_IMAGE, process.argv.at(-1));
    JAVASCRIPT
    runner.flush

    output = described_class.new(
      segments:,
      line_colour: "#206bc4",
      theme: "dark",
      style_url: "https://tiles.example.test/dark.json",
      runner_path: runner.path,
      process_environment: { "FAKE_ROUTE_IMAGE" => fixture.path, "CAPTURED_PAYLOAD" => captured.path }
    ).call

    payload = JSON.parse(captured.read)
    expect(payload).to include("theme" => "dark", "styleUrl" => "https://tiles.example.test/dark.json")

    expect do
      described_class.new(segments:, line_colour: "#206bc4", theme: "sepia")
    end.to raise_error(ArgumentError, "invalid route image theme")
  ensure
    output&.close!
    captured&.close!
  end

  it "hands a virtual world image over as a data URL instead of a tile style" do
    captured = Tempfile.new("route-payload", binmode: true)
    runner.write(<<~JAVASCRIPT)
      import fs from "node:fs";
      fs.writeFileSync(process.env.CAPTURED_PAYLOAD, fs.readFileSync(0));
      fs.copyFileSync(process.env.FAKE_ROUTE_IMAGE, process.argv.at(-1));
    JAVASCRIPT
    runner.flush

    basemap = Allure::Virtual::Basemap.new(
      image: "virtual_worlds/zwift/watopia-f4991742.webp",
      bounds: [ 166.87747, -11.74087, 167.03255, -11.62597 ],
      background: "#0884e2"
    )
    output = nil
    Dir.mktmpdir do |public_root|
      image = Pathname(public_root).join(basemap.image)
      image.dirname.mkpath
      Vips::Image.black(8, 8).webpsave(image.to_s)

      output = described_class.new(
        segments:,
        line_colour: "#206bc4",
        virtual_basemap: basemap,
        public_root:,
        runner_path: runner.path,
        process_environment: { "FAKE_ROUTE_IMAGE" => fixture.path, "CAPTURED_PAYLOAD" => captured.path }
      ).call

      payload = JSON.parse(captured.read)
      expect(payload).not_to have_key("styleUrl")
      expect(payload.dig("virtualBasemap", "image")).to start_with("data:image/webp;base64,")
      expect(payload.dig("virtualBasemap", "background")).to eq("#0884e2")
      expect(payload.dig("virtualBasemap", "darkBackground")).to eq("#032a48")
      expect(payload.dig("virtualBasemap", "coordinates")).to eq(basemap.coordinates)
    end
  ensure
    output&.close!
    captured&.close!
  end

  it "rejects a virtual basemap that is not a world image" do
    expect do
      described_class.new(segments:, line_colour: "#206bc4", virtual_basemap: { image: "x" })
    end.to raise_error(ArgumentError, "invalid virtual basemap")
  end
end
