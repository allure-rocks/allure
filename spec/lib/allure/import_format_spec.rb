# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::ImportFormat do
  def detect(bytes) = described_class.detect(StringIO.new(bytes.b))

  describe ".detect" do
    it "recognises a FIT file by its header size and signature" do
      bytes = build_fit(points: simple_fit_points)

      expect(detect(bytes)).to eq(described_class::FIT)
    end

    it "recognises a FIT file with a 12-byte header" do
      bytes = FitBuilder.new
        .define(local: 0, global: 0, fields: [ [ 0, :enum ] ])
        .data(local: 0, values: [ 4 ])
        .to_s(header_size: 12)

      expect(detect(bytes)).to eq(described_class::FIT)
    end

    it "recognises an XML declaration" do
      expect(detect(%(<?xml version="1.0"?><gpx version="1.1"></gpx>))).to eq(described_class::GPX)
    end

    it "recognises a bare gpx root element" do
      expect(detect("<gpx version=\"1.1\"></gpx>")).to eq(described_class::GPX)
    end

    it "looks past leading whitespace and a byte-order mark" do
      expect(detect("\xEF\xBB\xBF\n  <?xml version=\"1.0\"?><gpx/>")).to eq(described_class::GPX)
    end

    it "discriminates TCX by its root element, not the shared xml prefix" do
      expect(detect(%(<?xml version="1.0"?><TrainingCenterDatabase></TrainingCenterDatabase>))).to eq(described_class::TCX)
    end

    it "discriminates KML by its root element" do
      expect(detect(%(<?xml version="1.0"?><kml xmlns="http://www.opengis.net/kml/2.2"></kml>))).to eq(described_class::KML)
      expect(detect("<kml></kml>")).to eq(described_class::KML)
    end

    it "looks past comments and processing instructions to find the root" do
      expect(detect(%(<!-- a comment --><?xml version="1.0"?><?pi data?><TrainingCenterDatabase/>))).to eq(described_class::TCX)
      expect(detect(%(<!-- a comment --><gpx/>))).to eq(described_class::GPX)
    end

    it "fails closed when a long preamble pushes the root past the sniff window" do
      preamble = %(<?xml version="1.0"?>) + ("<!--" + ("x" * 1100) + "-->")
      expect(detect(preamble + "<gpx/>")).to be_nil
      expect(detect(preamble + "<TrainingCenterDatabase/>")).to be_nil
    end

    it "returns nil for content matching no supported format" do
      expect(detect("PK\x03\x04 this is a zip")).to be_nil
      expect(detect("<html><body>nope</body></html>")).to be_nil
      expect(detect("")).to be_nil
    end

    it "returns nil for a file too short to carry a FIT signature" do
      expect(detect("\x0E\x20\x3C")).to be_nil
    end

    it "returns nil when the signature is present but the header size is not" do
      bytes = build_fit(points: simple_fit_points).dup
      bytes.setbyte(0, 99)

      expect(detect(bytes)).to be_nil
    end

    it "rewinds the stream so a parser can read it afterwards" do
      io = StringIO.new(build_fit(points: simple_fit_points).b)

      described_class.detect(io)

      expect(io.pos).to eq(0)
      expect(Allure::Fit::Parser.new.parse(io).points_count).to eq(3)
    end
  end

  describe "content over extension" do
    # The extension is supplied by whoever uploaded or zipped the file. Only
    # the bytes are authoritative.
    it "detects FIT content regardless of what the file claims to be" do
      expect(detect(build_fit(points: simple_fit_points))).to eq(described_class::FIT)
      expect(described_class.for_extension(".gpx")).to eq(described_class::GPX)
    end
  end

  describe ".for_extension" do
    it "matches case-insensitively" do
      expect(described_class.for_extension(".FIT")).to eq(described_class::FIT)
      expect(described_class.for_extension(".Gpx")).to eq(described_class::GPX)
    end

    it "returns nil for an unsupported extension" do
      expect(described_class.for_extension(".txt")).to be_nil
      expect(described_class.for_extension("")).to be_nil
    end
  end

  describe ".for_key" do
    it "resolves a persisted import_format value" do
      expect(described_class.for_key("fit")).to eq(described_class::FIT)
      expect(described_class.for_key("txt")).to be_nil
    end
  end

  describe "format definitions" do
    it "pairs each key with a parser and a distinct extension" do
      expect(described_class::ALL.map(&:key)).to eq(Workout::IMPORT_FORMATS)
      expect(described_class::EXTENSIONS).to eq([ ".gpx", ".fit", ".tcx", ".kml" ])
      expect(described_class::GPX.parser).to be_a(Allure::Gpx::Parser)
      expect(described_class::FIT.parser).to be_a(Allure::Fit::Parser)
      expect(described_class::TCX.parser).to be_a(Allure::Tcx::Parser)
      expect(described_class::KML.parser).to be_a(Allure::Kml::Parser)
    end
  end
end
