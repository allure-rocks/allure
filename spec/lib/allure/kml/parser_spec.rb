# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Kml::Parser do
  describe "value extraction" do
    it "tolerates a whitespace prologue before the XML declaration" do
      content = "  \n " + File.read(kml_fixture_path("normal"))

      track = described_class.new.parse(StringIO.new(content))

      expect(track.segments.first.points.length).to eq(3)
    end

    it "parses timed gx:Track points in document order" do
      track = parse_kml_fixture("normal")

      expect(track.segments.length).to eq(1)
      expect(track.segments.first.points.length).to eq(3)
      expect(track.segments.first.points.first.latitude).to eq(45.0640)
      expect(track.segments.first.points.first.longitude).to eq(6.4077)
      expect(track.segments.first.points.first.elevation).to be_nil
      expect(track.segments.first.points.map(&:time)).to eq([
        Time.utc(2026, 8, 28, 8, 0, 0),
        Time.utc(2026, 8, 28, 8, 1, 0),
        Time.utc(2026, 8, 28, 8, 2, 0)
      ])
    end

    it "parses altitudes when present" do
      track = parse_kml_fixture("with_altitude")

      expect(track.segments.first.points.map(&:elevation)).to eq([ 1500.0, 1510.0, 1520.0 ])
    end

    it "emits kml name and description signals for the detector (resolved in 4.3)" do
      track = parse_kml_fixture("normal")

      expect(track.activity_signals).to include(
        have_attributes(source: :kml_name, value: "Morning run"),
        have_attributes(source: :kml_description, value: "A lakeside jog")
      )
    end

    it "ignores lap-like content and never produces laps" do
      track = parse_kml_fixture("with_lap")

      expect(track.segments.first.points.length).to eq(3)
      expect(track.laps).to be_empty
    end
  end

  describe "failures" do
    it "rejects a file with no timed track" do
      expect { parse_kml_fixture("no_points") }.to raise_error(Allure::Gpx::NoTrackError)
    end

    it "rejects a timeless LineString rather than fabricating timestamps" do
      xml = <<~KML
        <?xml version="1.0"?>
        <kml xmlns="http://www.opengis.net/kml/2.2">
          <Document><Placemark><name>Route</name>
            <LineString><coordinates>6.4,45.0,0 6.41,45.01,0 6.42,45.02,0</coordinates></LineString>
          </Placemark></Document>
        </kml>
      KML

      expect { described_class.new.parse(StringIO.new(xml)) }.to raise_error(Allure::Gpx::NoTrackError)
    end

    it "rejects malformed XML without a 500-worthy crash" do
      xml = <<~KML
        <?xml version="1.0"?>
        <kml xmlns="http://www.opengis.net/kml/2.2"><Document><Placemark>
          <gx:Track><when>2026-01-01T00:00:00Z</when>
      KML

      expect { described_class.new.parse(StringIO.new(xml)) }.to raise_error(Allure::Gpx::MalformedXmlError)
    end

    it "rejects non-monotonic track times" do
      xml = <<~KML
        <?xml version="1.0"?>
        <kml xmlns="http://www.opengis.net/kml/2.2" xmlns:gx="http://www.google.com/kml/ext/2.2">
          <Document><Placemark><gx:Track>
            <when>2026-01-01T00:01:00Z</when><gx:coord>6.0 45.0</gx:coord>
            <when>2026-01-01T00:00:00Z</when><gx:coord>6.001 45.001</gx:coord>
          </gx:Track></Placemark></Document>
        </kml>
      KML

      expect { described_class.new.parse(StringIO.new(xml)) }.to raise_error(Allure::Gpx::NonMonotonicTimestampError)
    end

    it "rejects a document whose root is not kml" do
      xml = <<~XML
        <?xml version="1.0"?>
        <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1"><trk><trkseg>
          <trkpt lat="1" lon="2"><time>2026-01-01T00:00:00Z</time></trkpt>
          <trkpt lat="1.01" lon="2"><time>2026-01-01T00:01:00Z</time></trkpt>
        </trkseg></trk></gpx>
      XML

      expect { described_class.new.parse(StringIO.new(xml)) }.to raise_error(Allure::Gpx::UnsupportedGpxError)
    end

    it "skips a malformed pair but keeps the valid points" do
      xml = <<~KML
        <?xml version="1.0"?>
        <kml xmlns="http://www.opengis.net/kml/2.2" xmlns:gx="http://www.google.com/kml/ext/2.2">
          <Document><Placemark><gx:Track>
            <when>2026-01-01T00:00:00Z</when><gx:coord>6.0 45.0</gx:coord>
            <when>not-a-time</when><gx:coord>6.001 45.001</gx:coord>
            <when>2026-01-01T00:02:00Z</when><gx:coord>6.002 45.002</gx:coord>
          </gx:Track></Placemark></Document>
        </kml>
      KML

      track = described_class.new.parse(StringIO.new(xml))

      expect(track.points_count).to eq(2)
    end
  end

  describe "limits" do
    it "enforces the shared coordinate limit while reading" do
      expect { parse_kml_fixture("normal", max_points: 2) }.to raise_error(Allure::Gpx::TooManyPointsError)
    end

    def kml(body)
      %(<kml xmlns="http://www.opengis.net/kml/2.2" xmlns:gx="http://www.google.com/kml/ext/2.2">) +
        "<Document>#{body}"
    end

    def timed_track(count)
      whens = Array.new(count) { |index| "<when>#{(Time.utc(2026, 8, 28) + index).iso8601}</when>" }
      coords = Array.new(count) { |index| "<gx:coord>6.#{index.to_s.rjust(6, '0')} 45.0</gx:coord>" }
      "<Placemark><gx:Track>#{whens.join}#{coords.join}</gx:Track></Placemark>"
    end

    it "refuses unreadable when elements past the limit before the track ends" do
      unclosed = kml("<Placemark><gx:Track>#{'<when/>' * (described_class::DEFAULT_MAX_POINTS + 1)}")

      expect { described_class.new.parse(StringIO.new(unclosed)) }
        .to raise_error(Allure::Gpx::TooManyPointsError, /when elements/)
    end

    it "refuses coord elements past the limit, counted over every track" do
      tracks = Array.new(3) { "<Placemark><gx:Track>#{'<gx:coord>x</gx:coord>' * 4}</gx:Track></Placemark>" }

      expect { described_class.new(max_points: 10).parse(StringIO.new(kml("#{tracks.join}</Document></kml>"))) }
        .to raise_error(Allure::Gpx::TooManyPointsError, /coord elements/)
    end

    it "still reads a file holding exactly the limit" do
      track = described_class.new(max_points: 50).parse(StringIO.new(kml("#{timed_track(50)}</Document></kml>")))

      expect(track.points_count).to eq(50)
    end

    it "keeps a bounded number of sport signals" do
      placemarks = Array.new(100) { |index| "<Placemark><name>Run #{index}</name></Placemark>" }
      track = described_class.new.parse(StringIO.new(kml("#{placemarks.join}#{timed_track(3)}</Document></kml>")))

      expect(track.activity_signals.length).to eq(Allure::Gpx::Parser::MAX_ACTIVITY_SIGNALS)
    end
  end
end
