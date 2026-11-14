# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workouts::ArchiveReader do
  let(:gpx) { Rails.root.join("spec/fixtures/gpx/galibier.gpx").binread }
  let(:fit) { build_fit(points: simple_fit_points) }

  def source_file(name, content)
    file = Tempfile.new([ "archive-reader-", File.extname(name) ])
    file.binmode
    file.write(content)
    file.rewind
    file.define_singleton_method(:original_filename) { name }
    file
  end

  def zip_source(entries)
    buffer = Zip::OutputStream.write_buffer do |zip|
      entries.each do |name, content|
        zip.put_next_entry(name)
        zip.write(content)
      end
    end
    source_file("activities.zip", buffer.string)
  end

  def gzip_content(content)
    buffer = StringIO.new
    Zlib::GzipWriter.wrap(buffer) { |gzip| gzip.write(content) }
    buffer.string
  end

  it "reads a direct GPX source" do
    source = source_file("ride.gpx", gpx)
    entries = []

    described_class.new.each_entry(source, filename: "ride.gpx") { entries << it }

    expect(entries.map(&:name)).to eq([ "ride.gpx" ])
    expect(entries.first.io.read).to eq(gpx)
  ensure
    source&.close!
  end

  it "reads a direct FIT source" do
    source = source_file("ride.fit", fit)
    entries = []

    described_class.new.each_entry(source, filename: "ride.fit") { entries << it }

    expect(entries.map(&:name)).to eq([ "ride.fit" ])
    expect(entries.first.io.read).to eq(fit)
  ensure
    source&.close!
  end

  it "reads each GPX file from a ZIP without extracting paths" do
    source = zip_source("one.gpx" => gpx, "nested/two.gpx" => gpx, "readme.txt" => "ignored")
    entries = []

    described_class.new.each_entry(source, filename: "activities.zip") { entries << [ it.name, it.io.read ] }

    expect(entries.map(&:first)).to eq([ "one.gpx", "nested/two.gpx" ])
    expect(entries.map(&:last)).to all(eq(gpx))
  ensure
    source&.close!
  end

  it "reads mixed GPX and FIT files from a ZIP" do
    source = zip_source("one.gpx" => gpx, "nested/two.fit" => fit, "readme.txt" => "ignored")
    entries = []

    described_class.new.each_entry(source, filename: "activities.zip") { entries << [ it.name, it.io.read ] }

    expect(entries).to eq([ [ "one.gpx", gpx ], [ "nested/two.fit", fit ] ])
  ensure
    source&.close!
  end

  it "reads a gzip-compressed single GPX" do
    source = source_file("ride.gpx.gz", gzip_content(gpx))
    entries = []

    described_class.new.each_entry(source, filename: "ride.gpx.gz") { entries << [ it.name, it.io.read ] }

    expect(entries.first).to eq([ "ride.gpx", gpx ])
  ensure
    source&.close!
  end

  it "reads a gzip-compressed single FIT" do
    source = source_file("ride.fit.gz", gzip_content(fit))
    entries = []

    described_class.new.each_entry(source, filename: "ride.fit.gz") { entries << [ it.name, it.io.read ] }

    expect(entries).to eq([ [ "ride.fit", fit ] ])
  ensure
    source&.close!
  end

  it "reads gzip-compressed GPX and FIT files from a ZIP" do
    source = zip_source("one.gpx.gz" => gzip_content(gpx), "nested/two.fit.gz" => gzip_content(fit))
    entries = []

    described_class.new.each_entry(source, filename: "activities.zip") { entries << [ it.name, it.io.read ] }

    expect(entries).to eq([ [ "one.gpx", gpx ], [ "nested/two.fit", fit ] ])
  ensure
    source&.close!
  end

  it "uses the detected format for a misleading gzip extension" do
    source = source_file("ride.gpx.gz", gzip_content(fit))
    entries = []

    described_class.new.each_entry(source, filename: "ride.gpx.gz") { entries << [ it.name, it.io.read ] }

    expect(entries).to eq([ [ "ride.fit", fit ] ])
  ensure
    source&.close!
  end

  it "rejects unsafe ZIP paths" do
    source = zip_source("../ride.gpx" => gpx)

    expect do
      described_class.new.each_entry(source, filename: "activities.zip") { }
    end.to raise_error(described_class::Error, /chemin d'archive non sûr/)
  ensure
    source&.close!
  end

  it "rejects an archive with no track entries" do
    source = zip_source("readme.txt" => "ignored")

    expect do
      described_class.new.each_entry(source, filename: "activities.zip") { }
    end.to raise_error(described_class::Error, /ne contient aucun fichier GPX, FIT, TCX ou KML/)
  ensure
    source&.close!
  end

  it "ignores unsupported gzip activities in a ZIP" do
    source = zip_source("activity.txt.gz" => gzip_content("not a supported track"))

    expect do
      described_class.new.each_entry(source, filename: "activities.zip") { }
    end.to raise_error(described_class::Error, /ne contient aucun fichier GPX, FIT, TCX ou KML/)
  ensure
    source&.close!
  end

  describe "KMZ and KML" do
    let(:kml) { Rails.root.join("spec/fixtures/kml/normal.kml").binread }

    def kmz_source(kml_content, member: "doc.kml", filename: "ride.kmz")
      buffer = Zip::OutputStream.write_buffer do |zip|
        zip.put_next_entry(member)
        zip.write(kml_content)
      end
      source_file(filename, buffer.string)
    end

    it "reads a KMZ single source as one KML entry" do
      source = kmz_source(kml)
      entries = []

      described_class.new.each_entry(source, filename: "ride.kmz") do |entry|
        entries << [ entry.name, entry.io.read ]
      end

      expect(entries).to eq([ [ "ride.kml", kml ] ])
    ensure
      source&.close!
    end

    it "reads KML files inside a ZIP" do
      source = zip_source("track.kml" => kml, "ride.gpx" => gpx)
      entries = []

      described_class.new.each_entry(source, filename: "activities.zip") { entries << it }

      expect(entries.map(&:name)).to contain_exactly("track.kml", "ride.gpx")
    ensure
      source&.close!
    end

    it "does not recurse into a KMZ inside a ZIP" do
      kmz_bytes = Zip::OutputStream.write_buffer do |zip|
        zip.put_next_entry("doc.kml")
        zip.write(kml)
      end.string
      source = zip_source("nested.kmz" => kmz_bytes, "ride.gpx" => gpx)
      entries = []

      described_class.new.each_entry(source, filename: "activities.zip") { entries << it }

      expect(entries.map(&:name)).to eq([ "ride.gpx" ])
    ensure
      source&.close!
    end

    it "rejects a KMZ with no KML member" do
      source = kmz_source("just text", member: "readme.txt")

      expect do
        described_class.new.each_entry(source, filename: "ride.kmz") { }
      end.to raise_error(described_class::Error, /ne contient aucun fichier GPX, FIT, TCX ou KML/)
    ensure
      source&.close!
    end

    it "rejects a corrupt KMZ as a malformed archive" do
      source = source_file("ride.kmz", "PK not really a zip")

      expect do
        described_class.new.each_entry(source, filename: "ride.kmz") { }
      end.to raise_error(described_class::Error)
    ensure
      source&.close!
    end
  end

  describe "#each_manifest_entry" do
    def manifest_pairs(source, filename)
      pairs = []
      described_class.new.each_manifest_entry(source, filename:) { pairs << [ it.name, it.index ] }
      pairs
    end

    def extraction_pairs(source, filename)
      pairs = []
      described_class.new.each_entry(source, filename:) { pairs << [ it.name, it.index ] }
      pairs
    end

    it "lists exactly the members extraction yields for a mixed ZIP" do
      source = zip_source(
        "one.gpx" => gpx,
        "nested/two.fit.gz" => gzip_content(fit),
        "readme.txt" => "ignored"
      )

      expect(manifest_pairs(source, "activities.zip")).to eq(extraction_pairs(source, "activities.zip"))
    ensure
      source&.close!
    end

    it "matches extraction names and indexes for every single-source kind" do
      kml = Rails.root.join("spec/fixtures/kml/normal.kml").binread
      kmz = Zip::OutputStream.write_buffer do |zip|
        zip.put_next_entry("doc.kml")
        zip.write(kml)
      end.string
      sources = [
        [ source_file("ride.gpx", gpx), "ride.gpx" ],
        [ source_file("ride.fit.gz", gzip_content(fit)), "ride.fit.gz" ],
        [ source_file("ride.kmz", kmz), "ride.kmz" ]
      ]

      sources.each do |source, filename|
        expect(manifest_pairs(source, filename)).to eq(extraction_pairs(source, filename))
      ensure
        source&.close!
      end
    end

    it "keeps a provisional gzip name until extraction detects the format" do
      source = source_file("ride.gpx.gz", gzip_content(fit))

      expect(manifest_pairs(source, "ride.gpx.gz")).to eq([ [ "ride.gpx", 0 ] ])
      expect(extraction_pairs(source, "ride.gpx.gz")).to eq([ [ "ride.fit", 0 ] ])
    ensure
      source&.close!
    end

    it "raises the same archive errors as extraction" do
      unsafe = zip_source("../ride.gpx" => gpx)
      empty = zip_source("readme.txt" => "ignored")
      unsupported = source_file("ride.txt", "not a track")
      corrupt = source_file("activities.zip", "not a zip")

      expect { manifest_pairs(unsafe, "activities.zip") }
        .to raise_error(described_class::Error, /chemin d'archive non sûr/)
      expect { manifest_pairs(empty, "activities.zip") }
        .to raise_error(described_class::Error, /ne contient aucun fichier GPX, FIT, TCX ou KML/)
      expect { manifest_pairs(unsupported, "ride.txt") }
        .to raise_error(described_class::Error, /format source non pris en charge/)
      expect { manifest_pairs(corrupt, "activities.zip") }
        .to raise_error(described_class::Error)
    ensure
      [ unsafe, empty, unsupported, corrupt ].each { |source| source&.close! }
    end
  end

  describe "a central directory declaring too many entries (PLAN_IMPORT_SOURCES.md §3.2)" do
    it "refuses a ZIP or a KMZ before rubyzip reads its directory" do
      expect(Zip::File).not_to receive(:open_buffer)

      { "bomb.zip" => 20_000, "bomb.kmz" => 2_000_000 }.each do |name, count|
        source = source_file(name, zip_declaring(count))

        expect { described_class.new.each_entry(source, filename: name) { nil } }
          .to raise_error(described_class::Error, /trop d'entrées \(maximum : 10000\)/)
        expect { described_class.new.each_manifest_entry(source, filename: name) { nil } }
          .to raise_error(described_class::Error, /trop d'entrées/) if name.end_with?(".zip")
      ensure
        source&.close!
      end
    end
  end
end
