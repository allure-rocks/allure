# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Tcx::Parser do
  describe "value extraction" do
    it "parses creator, description, calories, and points in document order" do
      track = parse_tcx_fixture("normal")

      expect(track.creator).to eq("Allure Test Suite")
      expect(track.description).to be_nil
      expect(track.calories).to eq(30)
      expect(track.segments.length).to eq(1)
      expect(track.segments.first.points.length).to eq(3)
      expect(track.segments.first.points.first.latitude).to eq(45.0640)
      expect(track.segments.first.points.first.longitude).to eq(6.4077)
      expect(track.segments.first.points.first.elevation).to eq(2000.0)
    end

    it "tolerates a whitespace prologue before the XML declaration" do
      content = "          " + File.read(tcx_fixture_path("normal"))

      track = described_class.new.parse(StringIO.new(content))

      expect(track.segments.first.points.length).to eq(3)
    end

    it "tolerates a UTF-8 BOM before the XML declaration" do
      content = "\xEF\xBB\xBF".b + File.read(tcx_fixture_path("normal")).b

      track = described_class.new.parse(StringIO.new(content))

      expect(track.segments.first.points.length).to eq(3)
    end

    it "emits a tcx_sport signal for the detector (resolved once the confidence key lands in 4.3)" do
      track = parse_tcx_fixture("normal")

      expect(track.activity_signals).to include(have_attributes(source: :tcx_sport, value: "run"))
    end

    it "emits no signal for a sport outside the mapped set" do
      xml = <<~TCX
        <?xml version="1.0"?>
        <TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">
          <Activities><Activity Sport="Skydiving"><Id>2026-01-01T00:00:00Z</Id>
            <Lap StartTime="2026-01-01T00:00:00Z"><TotalTimeSeconds>60</TotalTimeSeconds>
              <Track>
                <Trackpoint><Time>2026-01-01T00:00:00Z</Time><Position><LatitudeDegrees>45.0</LatitudeDegrees><LongitudeDegrees>6.0</LongitudeDegrees></Position></Trackpoint>
                <Trackpoint><Time>2026-01-01T00:01:00Z</Time><Position><LatitudeDegrees>45.001</LatitudeDegrees><LongitudeDegrees>6.001</LongitudeDegrees></Position></Trackpoint>
              </Track>
            </Lap>
          </Activity></Activities>
        </TrainingCenterDatabase>
      TCX

      expect(described_class.new.parse(StringIO.new(xml)).activity_signals).to be_empty
    end

    it "parses heart rate, cadence, and namespaced power extensions" do
      track = parse_tcx_fixture("with_sensors")
      points = track.segments.first.points

      expect(points.map(&:heart_rate)).to eq([ 140, 150, 160 ])
      expect(points.map(&:cadence)).to eq([ 80, 82, 84 ])
      expect(points.map(&:power)).to eq([ 200, 210, 220 ])
      expect(track.activity_signals).to include(have_attributes(source: :tcx_sport, value: "ride"))
    end

    it "treats zero heart rate as missing (strap dropout)" do
      xml = <<~TCX
        <?xml version="1.0"?>
        <TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">
          <Activities><Activity Sport="Running"><Id>2026-01-01T00:00:00Z</Id>
            <Lap StartTime="2026-01-01T00:00:00Z">
              <TotalTimeSeconds>120</TotalTimeSeconds>
              <AverageHeartRateBpm><Value>0</Value></AverageHeartRateBpm>
              <MaximumHeartRateBpm><Value>0</Value></MaximumHeartRateBpm>
              <Track>
                <Trackpoint><Time>2026-01-01T00:00:00Z</Time><Position><LatitudeDegrees>45.0</LatitudeDegrees><LongitudeDegrees>6.0</LongitudeDegrees></Position><HeartRateBpm><Value>0</Value></HeartRateBpm></Trackpoint>
                <Trackpoint><Time>2026-01-01T00:01:00Z</Time><Position><LatitudeDegrees>45.001</LatitudeDegrees><LongitudeDegrees>6.001</LongitudeDegrees></Position><HeartRateBpm><Value>140</Value></HeartRateBpm></Trackpoint>
              </Track>
            </Lap>
          </Activity></Activities>
        </TrainingCenterDatabase>
      TCX

      track = described_class.new.parse(StringIO.new(xml))

      expect(track.segments.first.points.map(&:heart_rate)).to eq([ nil, 140 ])
      expect(track.laps.first.average_heart_rate).to be_nil
      expect(track.laps.first.max_heart_rate).to be_nil
    end

    it "skips positionless trackpoints without failing the import" do
      xml = <<~TCX
        <?xml version="1.0"?>
        <TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">
          <Activities><Activity Sport="Running"><Id>2026-01-01T00:00:00Z</Id>
            <Lap StartTime="2026-01-01T00:00:00Z"><TotalTimeSeconds>120</TotalTimeSeconds>
              <Track>
                <Trackpoint><Time>2026-01-01T00:00:00Z</Time><HeartRateBpm><Value>140</Value></HeartRateBpm></Trackpoint>
                <Trackpoint><Time>2026-01-01T00:01:00Z</Time><Position><LatitudeDegrees>45.0</LatitudeDegrees><LongitudeDegrees>6.0</LongitudeDegrees></Position></Trackpoint>
                <Trackpoint><Time>2026-01-01T00:02:00Z</Time><Position><LatitudeDegrees>45.001</LatitudeDegrees><LongitudeDegrees>6.001</LongitudeDegrees></Position></Trackpoint>
              </Track>
            </Lap>
          </Activity></Activities>
        </TrainingCenterDatabase>
      TCX

      track = described_class.new.parse(StringIO.new(xml))

      expect(track.points_count).to eq(2)
      expect(track.segments.first.first_point.time).to eq(Time.utc(2026, 1, 1, 0, 1, 0))
    end

    it "imports a file whose trackpoints carry no position as a positionless recording" do
      track = described_class.new.parse(StringIO.new(indoor_tcx))

      expect(track).not_to be_positioned
      expect(track.points_count).to eq(3)
      points = track.segments.first.points
      expect(points.map(&:heart_rate)).to eq([ 120, 130, 140 ])
      expect(points.map(&:distance)).to eq([ 0.0, 500.0, 1000.0 ])
      expect(points.map(&:speed)).to eq([ nil, 8.0, 8.2 ])
      expect(points.map(&:power)).to eq([ 200, 210, 220 ])
    end

    it "drops an untimed positionless trackpoint rather than failing the import" do
      xml = indoor_tcx.sub(
        "<Trackpoint><Time>2026-01-01T00:02:00Z</Time>",
        "<Trackpoint><Time>2026-01-01T00:01:30Z</Time>"
      )
      xml = xml.sub(
        "<Trackpoint><Time>2026-01-01T00:01:30Z</Time><HeartRateBpm><Value>130</Value></HeartRateBpm></Trackpoint>",
        "<Trackpoint><HeartRateBpm><Value>125</Value></HeartRateBpm></Trackpoint>"
      )

      track = described_class.new.parse(StringIO.new(xml))

      expect(track.points_count).to eq(3)
      expect(track.segments.first.points.map(&:heart_rate)).to eq([ 120, 130, 140 ])
    end

    it "keeps the file positioned when only one trackpoint lacks a fix" do
      xml = indoor_tcx.sub(
        "<Trackpoint><Time>2026-01-01T00:01:00Z</Time>",
        "<Trackpoint><Time>2026-01-01T00:01:00Z</Time><Position><LatitudeDegrees>45.0</LatitudeDegrees><LongitudeDegrees>6.0</LongitudeDegrees></Position>"
      ).sub(
        "<Trackpoint><Time>2026-01-01T00:02:00Z</Time>",
        "<Trackpoint><Time>2026-01-01T00:02:00Z</Time><Position><LatitudeDegrees>45.001</LatitudeDegrees><LongitudeDegrees>6.001</LongitudeDegrees></Position>"
      )

      track = described_class.new.parse(StringIO.new(xml))

      expect(track).to be_positioned
      expect(track.points_count).to eq(2)
    end
  end

  describe "recorded laps" do
    it "parses three recorded laps with file totals and trigger methods" do
      track = parse_tcx_fixture("with_laps")

      expect(track.laps.length).to eq(3)
      expect(track.laps.map(&:number)).to eq([ 1, 2, 3 ])
      expect(track.laps.map(&:elapsed_time)).to eq([ 90, 90, 90 ])
      expect(track.laps.map(&:moving_time)).to eq([ 90, 90, 90 ])
      expect(track.laps.map(&:distance)).to eq([ 405.0, 405.0, 405.0 ])
      expect(track.laps.map(&:max_speed)).to eq([ 6.0, 6.2, 5.9 ])
      expect(track.source_max_speed).to eq(6.2)
      expect(track.laps.map(&:average_heart_rate)).to eq([ 140, 145, 150 ])
      expect(track.laps.map { |l| l.lap_trigger }).to eq([ "manual", "distance", "time" ])
    end

    it "drops a lap without a StartTime rather than rejecting the import" do
      xml = <<~TCX
        <?xml version="1.0"?>
        <TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">
          <Activities><Activity Sport="Running"><Id>2026-01-01T00:00:00Z</Id>
            <Lap>
              <TotalTimeSeconds>60</TotalTimeSeconds>
              <Track>
                <Trackpoint><Time>2026-01-01T00:00:00Z</Time><Position><LatitudeDegrees>45.0</LatitudeDegrees><LongitudeDegrees>6.0</LongitudeDegrees></Position></Trackpoint>
                <Trackpoint><Time>2026-01-01T00:01:00Z</Time><Position><LatitudeDegrees>45.001</LatitudeDegrees><LongitudeDegrees>6.001</LongitudeDegrees></Position></Trackpoint>
              </Track>
            </Lap>
            <Lap StartTime="2026-01-01T00:01:00Z">
              <TotalTimeSeconds>60</TotalTimeSeconds>
              <Track>
                <Trackpoint><Time>2026-01-01T00:01:00Z</Time><Position><LatitudeDegrees>45.001</LatitudeDegrees><LongitudeDegrees>6.001</LongitudeDegrees></Position></Trackpoint>
                <Trackpoint><Time>2026-01-01T00:02:00Z</Time><Position><LatitudeDegrees>45.002</LatitudeDegrees><LongitudeDegrees>6.002</LongitudeDegrees></Position></Trackpoint>
              </Track>
            </Lap>
          </Activity></Activities>
        </TrainingCenterDatabase>
      TCX

      track = described_class.new.parse(StringIO.new(xml))

      expect(track.segments.first.points.length).to eq(4)
      expect(track.laps.length).to eq(1)
      expect(track.laps.first.number).to eq(2)
    end
  end

  describe "failures" do
    it "rejects malformed XML without a 500-worthy crash" do
      expect { parse_tcx_fixture("malformed") }.to raise_error(Allure::Gpx::MalformedXmlError)
    end

    it "rejects a lap-only file with no positioned trackpoints" do
      expect { parse_tcx_fixture("unsupported") }.to raise_error(Allure::Gpx::NoTrackError)
    end

    it "rejects a positioned trackpoint with no timestamp" do
      xml = <<~TCX
        <?xml version="1.0"?>
        <TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">
          <Activities><Activity Sport="Running"><Id>2026-01-01T00:00:00Z</Id>
            <Lap StartTime="2026-01-01T00:00:00Z"><TotalTimeSeconds>60</TotalTimeSeconds>
              <Track>
                <Trackpoint><Position><LatitudeDegrees>45.0</LatitudeDegrees><LongitudeDegrees>6.0</LongitudeDegrees></Position></Trackpoint>
                <Trackpoint><Time>2026-01-01T00:01:00Z</Time><Position><LatitudeDegrees>45.001</LatitudeDegrees><LongitudeDegrees>6.001</LongitudeDegrees></Position></Trackpoint>
              </Track>
            </Lap>
          </Activity></Activities>
        </TrainingCenterDatabase>
      TCX

      expect { described_class.new.parse(StringIO.new(xml)) }.to raise_error(Allure::Gpx::MissingTimestampError)
    end

    it "rejects non-monotonic timestamps" do
      xml = <<~TCX
        <?xml version="1.0"?>
        <TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2">
          <Activities><Activity Sport="Running"><Id>2026-01-01T00:00:00Z</Id>
            <Lap StartTime="2026-01-01T00:00:00Z"><TotalTimeSeconds>60</TotalTimeSeconds>
              <Track>
                <Trackpoint><Time>2026-01-01T00:01:00Z</Time><Position><LatitudeDegrees>45.0</LatitudeDegrees><LongitudeDegrees>6.0</LongitudeDegrees></Position></Trackpoint>
                <Trackpoint><Time>2026-01-01T00:00:00Z</Time><Position><LatitudeDegrees>45.001</LatitudeDegrees><LongitudeDegrees>6.001</LongitudeDegrees></Position></Trackpoint>
              </Track>
            </Lap>
          </Activity></Activities>
        </TrainingCenterDatabase>
      TCX

      expect { described_class.new.parse(StringIO.new(xml)) }.to raise_error(Allure::Gpx::NonMonotonicTimestampError)
    end

    it "rejects a document whose root is not TrainingCenterDatabase" do
      xml = <<~XML
        <?xml version="1.0"?>
        <gpx version="1.1" xmlns="http://www.topografix.com/GPX/1/1"><trk><trkseg>
          <trkpt lat="1" lon="2"><time>2026-01-01T00:00:00Z</time></trkpt>
          <trkpt lat="1.01" lon="2"><time>2026-01-01T00:01:00Z</time></trkpt>
        </trkseg></trk></gpx>
      XML

      expect { described_class.new.parse(StringIO.new(xml)) }.to raise_error(Allure::Gpx::UnsupportedGpxError)
    end
  end

  describe "limits" do
    it "enforces the shared trackpoint limit while reading" do
      expect { parse_tcx_fixture("normal", max_points: 2) }.to raise_error(Allure::Gpx::TooManyPointsError)
    end

    it "keeps a bounded number of sport signals" do
      repeated = %(<Activity Sport="Biking"><Id>2026-08-28T07:00:00Z</Id></Activity>) * 100
      xml = File.read(tcx_fixture_path("normal")).sub("<Activities>", "<Activities>#{repeated}")

      track = described_class.new.parse(StringIO.new(xml))

      expect(track.activity_signals.length).to eq(Allure::Gpx::Parser::MAX_ACTIVITY_SIGNALS)
    end
  end

  # A Garmin indoor export: DistanceMeters and TPX Speed on every trackpoint,
  # no Position anywhere (docs/dev/NO-GPS.md).
  def indoor_tcx
    <<~TCX
      <?xml version="1.0"?>
      <TrainingCenterDatabase xmlns="http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2"
        xmlns:ns3="http://www.garmin.com/xmlschemas/ActivityExtension/v2">
        <Activities><Activity Sport="Biking"><Id>2026-01-01T00:00:00Z</Id>
          <Lap StartTime="2026-01-01T00:00:00Z"><TotalTimeSeconds>120</TotalTimeSeconds><DistanceMeters>1000</DistanceMeters>
            <Track>
              <Trackpoint><Time>2026-01-01T00:00:00Z</Time><DistanceMeters>0</DistanceMeters><HeartRateBpm><Value>120</Value></HeartRateBpm>
                <Extensions><ns3:TPX><ns3:Watts>200</ns3:Watts></ns3:TPX></Extensions></Trackpoint>
              <Trackpoint><Time>2026-01-01T00:01:00Z</Time><DistanceMeters>500</DistanceMeters><HeartRateBpm><Value>130</Value></HeartRateBpm>
                <Extensions><ns3:TPX><ns3:Speed>8.0</ns3:Speed><ns3:Watts>210</ns3:Watts></ns3:TPX></Extensions></Trackpoint>
              <Trackpoint><Time>2026-01-01T00:02:00Z</Time><DistanceMeters>1000</DistanceMeters><HeartRateBpm><Value>140</Value></HeartRateBpm>
                <Extensions><ns3:TPX><ns3:Speed>8.2</ns3:Speed><ns3:Watts>220</ns3:Watts></ns3:TPX></Extensions></Trackpoint>
            </Track>
          </Lap>
        </Activity></Activities>
      </TrainingCenterDatabase>
    TCX
  end
end
