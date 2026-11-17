# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Gpx::Parser do
  describe "structure and value extraction" do
    it "parses creator, name, description, and points in document order" do
      track = parse_gpx_fixture("galibier")

      expect(track.creator).to eq("Allure Test Suite")
      expect(track.name).to eq("Col du Galibier")
      expect(track.description).to eq("Normal timed 3D route with known metrics")
      expect(track.segments.length).to eq(1)
      expect(track.segments.first.points.length).to eq(4)
      expect(track.segments.first.points.first.latitude).to eq(45.0640)
      expect(track.segments.first.points.first.longitude).to eq(6.4077)
      expect(track.segments.first.points.first.elevation).to eq(2000.0)
    end

    it "tolerates a whitespace prologue before the XML declaration" do
      content = "\n   " + File.read(gpx_fixture_path("galibier"))

      track = described_class.new.parse(StringIO.new(content))

      expect(track.segments.first.points.length).to eq(4)
    end

    it "flattens every trkseg from every trk into document order" do
      track = parse_gpx_fixture("multiple_tracks")

      expect(track.segments.length).to eq(2)
      expect(track.name).to eq("First device track")
      expect(track.segments.first.points.first.latitude).to eq(45.0000)
      expect(track.segments.last.points.first.latitude).to eq(45.0020)
    end

    it "ignores empty and one-point segments without raising" do
      track = parse_gpx_fixture("one_point_segments")

      expect(track.segments.length).to eq(1)
      expect(track.segments.first.points.length).to eq(2)
    end

    it "parses Garmin TrackPointExtension hr/cad/power and track-level calories" do
      track = parse_gpx_fixture("with_extensions")
      points = track.segments.first.points

      expect(points.map(&:heart_rate)).to eq([ 140, 150, 160 ])
      expect(points.map(&:cadence)).to eq([ 80, 82, 84 ])
      expect(points.map(&:power)).to eq([ 200, 210, 220 ])
      expect(track.calories).to eq(350)
    end

    it "retains standard and OsmAnd activity signals without classifying them" do
      xml = <<~GPX
        <?xml version="1.0"?>
        <gpx version="1.1" creator="OsmAnd"
             xmlns="http://www.topografix.com/GPX/1/1"
             xmlns:osmand="https://osmand.net/docs/technical/osmand-file-formats/osmand-gpx">
          <metadata>
            <name>Weekend Hike</name>
            <desc>A mountain outing</desc>
            <keywords>trail running, weekend</keywords>
            <extensions><osmand:activity>hiking</osmand:activity></extensions>
          </metadata>
          <trk>
            <name>Test track</name>
            <type>TrailRun</type>
            <trkseg>
              <trkpt lat="1" lon="2"><time>2026-01-01T00:00:00Z</time></trkpt>
              <trkpt lat="1.01" lon="2"><time>2026-01-01T00:01:00Z</time></trkpt>
            </trkseg>
          </trk>
          <extensions><osmand:route>mtb</osmand:route></extensions>
        </gpx>
      GPX

      track = described_class.new.parse(StringIO.new(xml))

      expect(track.activity_signals).to include(
        have_attributes(source: :gpx_keywords, value: "trail running, weekend"),
        have_attributes(source: :gpx_metadata_name, value: "Weekend Hike"),
        have_attributes(source: :gpx_metadata_description, value: "A mountain outing"),
        have_attributes(source: :osmand_activity, value: "hiking"),
        have_attributes(source: :gpx_track_type, value: "TrailRun"),
        have_attributes(source: :osmand_route, value: "mtb")
      )
    end

    it "accepts elevation 0.0 as present, not missing" do
      track = parse_gpx_fixture("sea_level")
      expect(track.segments.first.points.map(&:elevation)).to eq([ 0.0, 0.0, 0.0 ])
    end

    it "leaves elevation nil when absent from the file" do
      track = parse_gpx_fixture("no_elevation")
      expect(track.segments.first.points.map(&:elevation)).to all(be_nil)
    end

    it "treats exact zeros as missing in a partially recorded segment" do
      track = parse_gpx_fixture("zero_placeholders")

      expect(track.segments.first.points.map(&:elevation)).to all(be_nil)
    end

    it "normalizes the shortest longitude delta across the antimeridian" do
      track = parse_gpx_fixture("antimeridian")
      longitudes = track.segments.first.points.map(&:longitude)
      expect(longitudes).to eq([ 179.9990, -179.9990, -179.9980 ])
    end
  end

  describe "recorded laps" do
    it "parses three recorded laps from a three-lap file" do
      track = parse_gpx_fixture("three_laps_recorded")

      expect(track.laps.length).to eq(3)
      expect(track.laps.map(&:number)).to eq([ 1, 2, 3 ])
      expect(track.laps.map(&:elapsed_time)).to eq([ 90, 90, 90 ])
      expect(track.laps.map(&:moving_time)).to eq([ 90, 90, 90 ])
      expect(track.laps.map(&:distance)).to eq([ 405.0, 405.0, 405.0 ])
      expect(track.laps.map { |l| l.average_speed.round(3) }).to eq([ 4.5, 4.5, 4.5 ])
      expect(track.laps.map(&:average_pace)).to eq([ 222, 222, 222 ])
    end

    it "uses the last recorded point as the end of the final lap" do
      track = parse_gpx_fixture("three_laps_recorded")

      expect(track.laps.last.started_at).to eq(Time.utc(2026, 8, 28, 8, 3, 0))
      expect(track.laps.last.elapsed_time).to eq(90)
    end

    it "records no laps from a file that has none" do
      expect(parse_gpx_fixture("galibier").laps).to be_empty
    end

    it "drops a lap with a malformed time rather than rejecting the import" do
      xml = <<~GPX
        <?xml version="1.0"?>
        <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
          <trk>
            <trkseg>
              <trkpt lat="45.0" lon="6.0"><time>2026-01-01T00:00:00Z</time></trkpt>
              <trkpt lat="45.001" lon="6.001"><time>2026-01-01T00:01:00Z</time></trkpt>
              <trkpt lat="45.002" lon="6.002"><time>2026-01-01T00:02:00Z</time></trkpt>
            </trkseg>
            <lap><time>not-a-timestamp</time><dist>100.0</dist></lap>
          </trk>
        </gpx>
      GPX

      track = described_class.new.parse(StringIO.new(xml))

      expect(track.segments).not_to be_empty
      expect(track.laps).to be_empty
    end

    it "ignores a lap in metadata rather than treating it as a recorded boundary" do
      xml = <<~GPX
        <?xml version="1.0"?>
        <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
          <metadata>
            <lap><time>2026-01-01T00:00:00Z</time><dist>100.0</dist></lap>
          </metadata>
          <trk>
            <trkseg>
              <trkpt lat="45.0" lon="6.0"><time>2026-01-01T00:00:00Z</time></trkpt>
              <trkpt lat="45.001" lon="6.001"><time>2026-01-01T00:01:00Z</time></trkpt>
            </trkseg>
          </trk>
        </gpx>
      GPX

      expect(described_class.new.parse(StringIO.new(xml)).laps).to be_empty
    end
  end

  describe "error fixtures" do
    it "rejects a trkpt with no timestamp" do
      expect { parse_gpx_fixture("missing_time") }.to raise_error(Allure::Gpx::MissingTimestampError)
    end

    it "rejects non-monotonic timestamps within a segment" do
      expect { parse_gpx_fixture("reversed_time") }.to raise_error(Allure::Gpx::NonMonotonicTimestampError)
    end

    it "rejects a document with no valid track" do
      expect { parse_gpx_fixture("empty") }.to raise_error(Allure::Gpx::NoTrackError)
    end

    it "rejects malformed XML without a 500-worthy crash" do
      expect { parse_gpx_fixture("malformed") }.to raise_error(Allure::Gpx::MalformedXmlError)
    end

    it "never resolves an external entity and safely rejects the import" do
      expect { parse_gpx_fixture("external_entity") }.to raise_error(Allure::Gpx::MissingTimestampError)
    end
  end

  describe "limits and format validation" do
    it "enforces the configured trkpt limit while reading" do
      expect { parse_gpx_fixture("galibier", max_points: 2) }.to raise_error(Allure::Gpx::TooManyPointsError)
    end

    it "keeps a bounded number of sport signals" do
      repeated = "<trk><type>cycling</type></trk>" * 100
      xml = File.read(gpx_fixture_path("galibier")).sub("<trk>", "#{repeated}<trk>")

      track = described_class.new.parse(StringIO.new(xml))

      expect(track.activity_signals.length).to eq(described_class::MAX_ACTIVITY_SIGNALS)
    end

    it "rejects an unsupported GPX version" do
      xml = <<~GPX
        <?xml version="1.0"?>
        <gpx version="2.0" xmlns="http://www.topografix.com/GPX/1/1">
          <trk><trkseg>
            <trkpt lat="1" lon="2"><time>2026-01-01T00:00:00Z</time></trkpt>
            <trkpt lat="1.01" lon="2"><time>2026-01-01T00:01:00Z</time></trkpt>
          </trkseg></trk>
        </gpx>
      GPX

      expect { described_class.new.parse(StringIO.new(xml)) }.to raise_error(Allure::Gpx::UnsupportedGpxError)
    end

    it "rejects a document whose root element is not gpx" do
      xml = <<~XML
        <?xml version="1.0"?>
        <notgpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1"></notgpx>
      XML

      expect { described_class.new.parse(StringIO.new(xml)) }.to raise_error(Allure::Gpx::UnsupportedGpxError)
    end

    it "accepts the GPX 1.0 namespace and version" do
      xml = <<~GPX
        <?xml version="1.0"?>
        <gpx version="1.0" xmlns="http://www.topografix.com/GPX/1/0">
          <trk><trkseg>
            <trkpt lat="1" lon="2"><time>2026-01-01T00:00:00Z</time></trkpt>
            <trkpt lat="1.01" lon="2"><time>2026-01-01T00:01:00Z</time></trkpt>
          </trkseg></trk>
        </gpx>
      GPX

      track = described_class.new.parse(StringIO.new(xml))
      expect(track.segments.length).to eq(1)
    end

    it "rejects a coordinate outside its valid range" do
      xml = <<~GPX
        <?xml version="1.0"?>
        <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
          <trk><trkseg>
            <trkpt lat="95.0" lon="2"><time>2026-01-01T00:00:00Z</time></trkpt>
            <trkpt lat="1.01" lon="2"><time>2026-01-01T00:01:00Z</time></trkpt>
          </trkseg></trk>
        </gpx>
      GPX

      expect { described_class.new.parse(StringIO.new(xml)) }.to raise_error(Allure::Gpx::InvalidPointError)
    end

    it "rejects a malformed (non-numeric) elevation instead of silently ignoring it" do
      xml = <<~GPX
        <?xml version="1.0"?>
        <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1">
          <trk><trkseg>
            <trkpt lat="1" lon="2"><ele>not-a-number</ele><time>2026-01-01T00:00:00Z</time></trkpt>
            <trkpt lat="1.01" lon="2"><time>2026-01-01T00:01:00Z</time></trkpt>
          </trkseg></trk>
        </gpx>
      GPX

      expect { described_class.new.parse(StringIO.new(xml)) }.to raise_error(Allure::Gpx::InvalidPointError)
    end

    it "ignores a malformed optional extension value instead of rejecting the import" do
      xml = <<~GPX
        <?xml version="1.0"?>
        <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1"
             xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">
          <trk><trkseg>
            <trkpt lat="1" lon="2">
              <time>2026-01-01T00:00:00Z</time>
              <extensions><gpxtpx:TrackPointExtension><gpxtpx:hr>not-a-number</gpxtpx:hr></gpxtpx:TrackPointExtension></extensions>
            </trkpt>
            <trkpt lat="1.01" lon="2"><time>2026-01-01T00:01:00Z</time></trkpt>
          </trkseg></trk>
        </gpx>
      GPX

      track = described_class.new.parse(StringIO.new(xml))
      expect(track.segments.first.points.first.heart_rate).to be_nil
    end

    it "reads the Garmin air temperature and drops an implausible one (docs/dev/WEATHER.md)" do
      xml = <<~GPX
        <?xml version="1.0"?>
        <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1"
             xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">
          <trk><trkseg>
            <trkpt lat="1" lon="2">
              <time>2026-01-01T00:00:00Z</time>
              <extensions><gpxtpx:TrackPointExtension><gpxtpx:atemp>18.5</gpxtpx:atemp></gpxtpx:TrackPointExtension></extensions>
            </trkpt>
            <trkpt lat="1.01" lon="2">
              <time>2026-01-01T00:01:00Z</time>
              <extensions><gpxtpx:TrackPointExtension><gpxtpx:atemp>127</gpxtpx:atemp></gpxtpx:TrackPointExtension></extensions>
            </trkpt>
          </trkseg></trk>
        </gpx>
      GPX

      points = described_class.new.parse(StringIO.new(xml)).segments.first.points
      expect(points.map(&:temperature)).to eq([ 18.5, nil ])
      expect(Allure::Gpx::PointSerializer.serialize(time_offset_seconds: 0, cumulative_distance_metres: 0,
                                                    temperature: 18.5)).to include("temp" => 19)
    end

    it "treats zero heart rate as missing (strap dropout) while keeping zero cadence/power" do
      xml = <<~GPX
        <?xml version="1.0"?>
        <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1"
             xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1">
          <trk><trkseg>
            <trkpt lat="1" lon="2">
              <time>2026-01-01T00:00:00Z</time>
              <extensions><gpxtpx:TrackPointExtension><gpxtpx:hr>0</gpxtpx:hr><gpxtpx:cad>0</gpxtpx:cad></gpxtpx:TrackPointExtension></extensions>
            </trkpt>
            <trkpt lat="1.01" lon="2"><time>2026-01-01T00:01:00Z</time></trkpt>
          </trkseg></trk>
        </gpx>
      GPX

      track = described_class.new.parse(StringIO.new(xml))
      expect(track.segments.first.points.first.heart_rate).to be_nil
      expect(track.segments.first.points.first.cadence).to eq(0)
    end
  end
end
