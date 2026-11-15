# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Fit::Parser do
  let(:start) { Time.utc(2026, 5, 1, 8, 0, 0) }

  describe "value extraction" do
    it "produces the same Track contract the GPX parser produces" do
      track = parse_fit(build_fit(points: simple_fit_points(start:)))

      expect(track).to be_a(Allure::Gpx::Track)
      expect(track.segments.length).to eq(1)
      expect(track.segments.first).to be_a(Allure::Gpx::Segment)
      expect(track.segments.first.points.first).to be_a(Allure::Gpx::Point)
      expect(track.points_count).to eq(3)
    end

    it "converts semicircles to degrees" do
      track = parse_fit(build_fit(points: [
        { time: start, lat: 45.0640, lon: 6.4077 },
        { time: start + 60, lat: -33.8688, lon: 151.2093 }
      ]))
      points = track.segments.first.points

      # FIT stores coordinates as 32-bit semicircles, so roughly 8.4e-8
      # degrees of quantization is inherent to the format, not a defect.
      expect(points.first.latitude).to be_within(1e-6).of(45.0640)
      expect(points.first.longitude).to be_within(1e-6).of(6.4077)
      expect(points.last.latitude).to be_within(1e-6).of(-33.8688)
      expect(points.last.longitude).to be_within(1e-6).of(151.2093)
    end

    it "converts timestamps from the 1989-12-31 FIT epoch to UTC" do
      track = parse_fit(build_fit(points: simple_fit_points(start:)))

      expect(track.segments.first.points.map(&:time)).to eq([ start, start + 60, start + 120 ])
    end

    it "applies the altitude scale and offset" do
      track = parse_fit(build_fit(points: [
        { time: start, lat: 45.0, lon: 6.0, altitude: 2000.0 },
        { time: start + 60, lat: 45.001, lon: 6.001, altitude: -12.4 }
      ]))

      expect(track.segments.first.points.map(&:elevation)).to eq([ 2000.0, -12.4 ])
    end

    it "treats exact zeros as missing when other records carry no altitude" do
      track = parse_fit(build_fit(points: [
        { time: start, lat: 45.0, lon: 6.0 },
        { time: start + 60, lat: 45.001, lon: 6.001, altitude: 0.0 },
        { time: start + 120, lat: 45.002, lon: 6.002 }
      ]))

      expect(track.segments.first.points.map(&:elevation)).to all(be_nil)
    end

    it "keeps exact zeros when every record carries an altitude" do
      track = parse_fit(build_fit(points: [
        { time: start, lat: 45.0, lon: 6.0, altitude: 0.0 },
        { time: start + 60, lat: 45.001, lon: 6.001, altitude: 0.0 }
      ]))

      expect(track.segments.first.points.map(&:elevation)).to eq([ 0.0, 0.0 ])
    end

    it "prefers enhanced_altitude over altitude when both are present" do
      bytes = FitBuilder.new
        .define(local: 0, global: 0, fields: [ [ 0, :enum ] ])
        .data(local: 0, values: [ 4 ])
        .define(local: 1, global: 20, fields: [
          [ 253, :uint32 ], [ 0, :sint32 ], [ 1, :sint32 ], [ 2, :uint16 ], [ 78, :uint32 ]
        ])
        .data(local: 1, values: [
          FitBuilder.fit_time(start), FitBuilder.semicircles(45.0), FitBuilder.semicircles(6.0),
          ((100.0 + 500) * 5).round, ((2500.0 + 500) * 5).round
        ])
        .data(local: 1, values: [
          FitBuilder.fit_time(start + 60), FitBuilder.semicircles(45.001), FitBuilder.semicircles(6.001),
          ((110.0 + 500) * 5).round, ((2510.0 + 500) * 5).round
        ])
        .to_s

      expect(parse_fit(bytes).segments.first.points.map(&:elevation)).to eq([ 2500.0, 2510.0 ])
    end

    it "reads heart rate, cadence, and power, omitting absent values" do
      track = parse_fit(build_fit(points: [
        { time: start, lat: 45.0, lon: 6.0, hr: 142, cadence: 84, power: 210 },
        { time: start + 60, lat: 45.001, lon: 6.001 }
      ]))
      points = track.segments.first.points

      expect(points.first).to have_attributes(heart_rate: 142, cadence: 84, power: 210)
      expect(points.last).to have_attributes(heart_rate: nil, cadence: nil, power: nil)
    end

    it "reads the device's own speed in metres per second" do
      track = parse_fit(build_fit(points: [
        { time: start, lat: 45.0, lon: 6.0, speed: 4.25 },
        { time: start + 60, lat: 45.001, lon: 6.001 }
      ]))

      expect(track.segments.first.points.map(&:speed)).to eq([ 4.25, nil ])
    end

    it "treats zero heart rate as missing (strap dropout) while keeping zero cadence/power" do
      track = parse_fit(build_fit(points: [
        { time: start, lat: 45.0, lon: 6.0, hr: 0, cadence: 0, power: 0 },
        { time: start + 60, lat: 45.001, lon: 6.001, hr: 142, cadence: 84, power: 210 }
      ]))
      points = track.segments.first.points

      expect(points.first.heart_rate).to be_nil
      expect(points.first.cadence).to eq(0)
      expect(points.first.power).to eq(0)
      expect(points.last.heart_rate).to eq(142)
    end

    it "treats zero lap heart rates as missing" do
      laps = [ { time: start + 90, elapsed: 90, moving: 80, distance: 405, avg_heart_rate: 0, max_heart_rate: 0 } ]
      track = parse_fit(build_fit(points: (0..3).map { |i| { time: start + (i * 30), lat: 45.0 + i * 0.0005, lon: 6.0 } }, laps:))

      expect(track.laps.first.average_heart_rate).to be_nil
      expect(track.laps.first.max_heart_rate).to be_nil
    end

    it "reads total calories from the session message" do
      track = parse_fit(build_fit(points: simple_fit_points(start:), calories: 742))

      expect(track.calories).to eq(742)
    end

    it "leaves name and description nil so the importer supplies a localized title" do
      track = parse_fit(build_fit(points: simple_fit_points(start:)))

      expect(track.name).to be_nil
      expect(track.description).to be_nil
    end
  end

  # Some devices declare position_lat/position_long as uint32 (0x86) instead of
  # the profile's sint32 (0x85) and write two's-complement negative
  # semicircles. Without the sign reinterpretation, every western or southern
  # coordinate exceeds the range and the whole import fails.
  describe "non-conformant position declarations" do
    it "reinterprets negative semicircles written as uint32" do
      track = parse_fit(build_fit(points: [
        { time: start, lat: 42.3394, lon: -71.0977 },
        { time: start + 60, lat: 42.3651, lon: -71.1421 }
      ], record_latlon_type: :uint32))
      points = track.segments.first.points

      expect(points.first.latitude).to be_within(1e-6).of(42.3394)
      expect(points.first.longitude).to be_within(1e-6).of(-71.0977)
      expect(points.last.longitude).to be_within(1e-6).of(-71.1421)
    end

    it "reinterprets negative semicircles written as big-endian uint32" do
      track = parse_fit(build_fit(points: [
        { time: start, lat: 51.5541, lon: -0.8712 },
        { time: start + 60, lat: 51.5316, lon: -0.8908 }
      ], record_latlon_type: :uint32, big_endian: true))
      points = track.segments.first.points

      expect(points.first.latitude).to be_within(1e-6).of(51.5541)
      expect(points.first.longitude).to be_within(1e-6).of(-0.8712)
    end

    it "keeps positive uint32 semicircles unchanged" do
      track = parse_fit(build_fit(points: simple_fit_points(start:), record_latlon_type: :uint32))
      points = track.segments.first.points

      expect(points.first.latitude).to be_within(1e-6).of(45.0640)
      expect(points.first.longitude).to be_within(1e-6).of(6.4077)
    end

    it "still refuses an out-of-range latitude written as uint32" do
      # Negative semicircles become valid longitudes but not valid latitudes;
      # the range check keeps rejecting impossible values.
      expect do
        parse_fit(build_fit(points: [
          { time: start, lat: -160.0, lon: 6.0 },
          { time: start + 60, lat: -159.9, lon: 6.001 }
        ], record_latlon_type: :uint32))
      end.to raise_error(Allure::Gpx::InvalidPointError, /latitude out of range/)
    end
  end

  describe "creator" do
    it "uses the device product name when present" do
      track = parse_fit(build_fit(points: simple_fit_points(start:), product_name: "Edge 1050"))

      expect(track.creator).to eq("Edge 1050")
    end

    it "falls back to the manufacturer name when no product name is recorded" do
      track = parse_fit(build_fit(points: simple_fit_points(start:), product_name: nil, manufacturer: 294))

      expect(track.creator).to eq("COROS")
    end

    it "names an iGPSPORT computer, which writes no product name" do
      track = parse_fit(build_fit(points: simple_fit_points(start:), product_name: nil, manufacturer: 115, product: 501))

      expect(track.creator).to eq("iGPSPORT")
    end

    it "names the Garmin model from its product code" do
      track = parse_fit(build_fit(points: simple_fit_points(start:), product_name: nil, manufacturer: 1, product: 4062))

      expect(track.creator).to eq("Garmin Edge 840")
    end

    it "folds a regional Garmin variant into its model" do
      track = parse_fit(build_fit(points: simple_fit_points(start:), product_name: nil, manufacturer: 1, product: 2130))

      expect(track.creator).to eq("Garmin Forerunner 920XT")
    end

    it "falls back to the manufacturer for an unknown product code" do
      track = parse_fit(build_fit(points: simple_fit_points(start:), product_name: nil, manufacturer: 1, product: 60_000))

      expect(track.creator).to eq("Garmin")
    end

    it "prefers the recorded product name over the product code" do
      track = parse_fit(build_fit(points: simple_fit_points(start:), product_name: "Edge 840 Solar",
                                  manufacturer: 1, product: 4062))

      expect(track.creator).to eq("Edge 840 Solar")
    end

    it "is nil for an unrecognised manufacturer rather than an opaque identifier" do
      track = parse_fit(build_fit(points: simple_fit_points(start:), product_name: nil, manufacturer: 60_000))

      expect(track.creator).to be_nil
    end

    it "names a registered virtual platform from its file_id fingerprint" do
      track = parse_fit(build_fit(
        points: simple_fit_points(start:),
        product_name: nil, manufacturer: 255, product: 22, serial_number: 1234
      ))

      expect(track.creator).to eq("EXR")
    end

    it "ignores a near-miss fingerprint" do
      track = parse_fit(build_fit(
        points: simple_fit_points(start:),
        product_name: nil, manufacturer: 255, product: 22, serial_number: 5678
      ))

      expect(track.creator).to be_nil
    end
  end

  # EXR draws its Bled race course at twice the distance rowed; the lap
  # distance the ergometer recorded is authoritative (docs/dev/VIRTUAL-PLATFORMS.md).
  describe "virtual platform distance" do
    let(:points) { (0..60).map { { time: start + it, lat: 46.368, lon: 14.1 - (it * 0.0001) } } }
    let(:drawn) do
      points.each_cons(2).sum { |a, b| Allure::Gpx::Geo.horizontal_distance(a[:lat], a[:lon], b[:lat], b[:lon]) }
    end
    let(:laps) { [ { time: start + 60, elapsed: 60, distance: (drawn / 2).round(2) } ] }

    def track_length(track)
      track.segments.sum do |segment|
        segment.points.each_cons(2).sum do |a, b|
          Allure::Gpx::Geo.horizontal_distance(a.latitude, a.longitude, b.latitude, b.longitude)
        end
      end
    end

    it "fits a registered platform's positions to its recorded lap distance" do
      track = parse_fit(build_fit(points:, laps:, product_name: nil, manufacturer: 255, product: 22, serial_number: 1234))

      expect(track_length(track)).to be_within(0.01).of((drawn / 2).round(2))
      expect(track.segments.first.points.map(&:time)).to eq(points.map { it[:time] })
    end

    it "never moves the positions of an ordinary device" do
      track = parse_fit(build_fit(points:, laps:))

      # Semicircle quantization alone moves the length by millimetres.
      expect(track_length(track)).to be_within(0.1).of(drawn)
    end
  end

  # A video route can end by moving the athlete elsewhere without moving them
  # (docs/dev/VIRTUAL-PLATFORMS.md). The jump must not draw a line across the map or
  # contaminate the speeds around it.
  describe "virtual platform teleports" do
    let(:points) do
      [
        { time: start, lat: 45.0, lon: 6.0, distance: 0 },
        { time: start + 1, lat: 45.0001, lon: 6.0, distance: 10 },
        { time: start + 2, lat: 45.0002, lon: 6.0, distance: 20 },
        { time: start + 3, lat: 46.0, lon: 7.0, distance: 30 },
        { time: start + 4, lat: 46.0001, lon: 7.0, distance: 40 },
        { time: start + 5, lat: 46.0002, lon: 7.0, distance: 50 }
      ]
    end
    let(:laps) { [ { time: start + 5, elapsed: 5, distance: 50 } ] }

    def track_length(track)
      track.segments.sum do |segment|
        segment.points.each_cons(2).sum do |a, b|
          Allure::Gpx::Geo.horizontal_distance(a.latitude, a.longitude, b.latitude, b.longitude)
        end
      end
    end

    it "starts a new segment at the jump and still fits the recorded distance" do
      track = parse_fit(build_fit(points:, laps:, product_name: nil, manufacturer: 144))

      expect(track.segments.map(&:size)).to eq([ 3, 3 ])
      expect(track.segments.first.last_point.latitude).to be_within(1e-4).of(45.0002)
      expect(track.segments.last.first_point.latitude).to be_within(1e-6).of(46.0)
      expect(track_length(track)).to be_within(0.01).of(50)
    end

    it "splits even when the file carries no lap to calibrate against" do
      track = parse_fit(build_fit(points:, product_name: nil, manufacturer: 144))

      expect(track.segments.map(&:size)).to eq([ 3, 3 ])
    end

    it "never splits an ordinary device's track" do
      track = parse_fit(build_fit(points:, laps:))

      expect(track.segments.length).to eq(1)
    end
  end

  describe "recording segments" do
    let(:points) do
      (0..5).map { { time: start + (it * 60), lat: 45.0 + (it * 0.001), lon: 6.0 + (it * 0.001) } }
    end

    it "starts a new segment on a timer stop_all event" do
      track = parse_fit(build_fit(points:, stops: [ start + 180 ]))

      expect(track.segments.map(&:size)).to eq([ 3, 3 ])
      expect(track.segments.first.last_point.time).to eq(start + 120)
      expect(track.segments.last.first_point.time).to eq(start + 180)
    end

    it "splits on every stop_all, not just the first" do
      track = parse_fit(build_fit(points:, stops: [ start + 120, start + 240 ]))

      expect(track.segments.map(&:size)).to eq([ 2, 2, 2 ])
    end

    it "places stop events by timestamp, because devices may write them after every record" do
      # build_fit emits all events before all records; the parser must still
      # split in the middle rather than at the beginning.
      track = parse_fit(build_fit(points:, stops: [ start + 180 ]))

      expect(track.segments.length).to eq(2)
    end

    it "drops a segment left with fewer than two points" do
      track = parse_fit(build_fit(points:, stops: [ start + 60 ]))

      expect(track.segments.map(&:size)).to eq([ 5 ])
    end

    it "keeps one segment when no stop_all event is present" do
      track = parse_fit(build_fit(points:))

      expect(track.segments.map(&:size)).to eq([ 6 ])
    end
  end

  describe "recorded laps" do
    let(:points) do
      (0..17).map { |i| { time: start + (i * 30), lat: 45.0 + (i % 4) * 0.0005, lon: 6.0 + (i % 4) * 0.0006 } }
    end

    let(:laps) do
      [
        { time: start + 90, elapsed: 90, moving: 80, distance: 405, avg_speed: 4.5, max_speed: 6.0, avg_heart_rate: 140, avg_cadence: 85, avg_power: 210, lap_trigger: 0 },
        { time: start + 180, elapsed: 90, moving: 85, distance: 380, avg_speed: 4.0, max_speed: 5.5, avg_heart_rate: 150, avg_cadence: 88, avg_power: 230, lap_trigger: 1 },
        { time: start + 270, elapsed: 90, moving: 70, distance: 410, avg_speed: 5.9, max_speed: 6.5, avg_heart_rate: 155, avg_cadence: 90, avg_power: 240, lap_trigger: 2 }
      ]
    end

    it "decodes the independent per-lap totals and official scales" do
      track = parse_fit(build_fit(points:, laps:))

      expect(track.laps.map(&:number)).to eq([ 1, 2, 3 ])
      expect(track.laps.map(&:elapsed_time)).to eq([ 90, 90, 90 ])
      expect(track.laps.map(&:moving_time)).to eq([ 80, 85, 70 ])
      expect(track.laps.map { |l| l.distance.round(1) }).to eq([ 405.0, 380.0, 410.0 ])
      # Speed is derived from the per-lap distance and moving time, not the
      # device's scaled value, so it matches the workout's own convention.
      [ 405.0 / 80, 380.0 / 85, 410.0 / 70 ].each_with_index do |expected, index|
        expect(track.laps[index].average_speed).to be_within(1e-3).of(expected)
      end
      expect(track.laps.map(&:average_heart_rate)).to eq([ 140, 150, 155 ])
      expect(track.laps.map(&:average_cadence)).to eq([ 85, 88, 90 ])
      expect(track.laps.map(&:max_speed)).to eq([ 6.0, 5.5, 6.5 ])
      expect(track.laps.map { |l| l.lap_trigger }).to eq([ "manual", "distance", "time" ])
    end


    it "prefers enhanced session maximum speed and falls back to lap maximums" do
      session_track = parse_fit(build_fit(points:, laps:, max_speed: 6.0, enhanced_max_speed: 6.25))
      lap_track = parse_fit(build_fit(points:, laps:))

      expect(session_track.source_max_speed).to eq(6.25)
      expect(lap_track.source_max_speed).to eq(6.5)
    end

    it "exposes the device's own elevation totals from the session message" do
      track = parse_fit(build_fit(points:, session_ascent: 123, session_descent: 45))
      without = parse_fit(build_fit(points:))

      expect(track.source_ascent).to eq(123)
      expect(track.source_descent).to eq(45)
      expect(without.source_ascent).to be_nil
      expect(without.source_descent).to be_nil
    end

    # Session field 21 is `max_power`; the elevation totals are 22 and 23,
    # one number above their lap counterparts. An Amazfit Balance 2 run with a
    # 443 W running-power maximum was read as a 443 m climb.
    it "does not read the session maximum power as the ascent total" do
      track = parse_fit(build_fit(points:, session_max_power: 443, session_ascent: 298, session_descent: 300))

      expect(track.source_ascent).to eq(298)
      expect(track.source_descent).to eq(300)
    end

    it "falls back to a positive legacy session maximum when enhanced speed is zero" do
      track = parse_fit(build_fit(points:, laps:, max_speed: 6.25, enhanced_max_speed: 0.0))

      expect(track.source_max_speed).to eq(6.25)
    end

    it "prefers enhanced lap speed fields" do
      enhanced_lap = laps.first.merge(enhanced_avg_speed: 5.25, enhanced_max_speed: 7.5)
      track = parse_fit(build_fit(points:, laps: [ enhanced_lap ]))

      expect(track.laps.first.max_speed).to eq(7.5)
      expect(track.source_max_speed).to eq(7.5)
    end

    it "masks message-index flags when numbering laps" do
      flagged_lap = laps.first.merge(message_index: 0x8005)
      track = parse_fit(build_fit(points:, laps: [ flagged_lap ]))

      expect(track.laps.first.number).to eq(6)
    end

    it "numbers laps sequentially when the device reuses the same message_index" do
      repeated = [
        { time: start + 300, elapsed: 300, distance: 1000, message_index: 0 },
        { time: start + 312, elapsed: 12, distance: 57, message_index: 0 },
        { time: start + 600, elapsed: 288, distance: 990, message_index: 0 }
      ]
      track = parse_fit(build_fit(points:, laps: repeated))

      expect(track.laps.map(&:number)).to eq([ 1, 2, 3 ])
    end

    it "keeps the file's numbering when only some indexes collide" do
      mixed = [
        { time: start + 300, elapsed: 300, distance: 1000, message_index: 4 },
        { time: start + 312, elapsed: 12, distance: 57, message_index: 4 },
        { time: start + 600, elapsed: 288, distance: 990, message_index: 0 }
      ]
      track = parse_fit(build_fit(points:, laps: mixed))

      expect(track.laps.map(&:number)).to eq([ 5, 6, 1 ])
    end

    it "derives started_at as the completion time minus the per-lap elapsed time" do
      track = parse_fit(build_fit(points:, laps: [ { time: start + 90, elapsed: 90, moving: 80, distance: 405 } ]))

      expect(track.laps.first.started_at).to eq(start)
    end

    it "caps moving_time at elapsed_time so a noisy total cannot fail persistence" do
      track = parse_fit(build_fit(points:, laps: [ { time: start + 90, elapsed: 60, moving: 80, distance: 405 } ]))

      expect(track.laps.first.moving_time).to eq(60)
    end

    it "returns an empty list when the file recorded no laps" do
      expect(parse_fit(build_fit(points: simple_fit_points(start:))).laps).to be_empty
    end
  end

  describe "record selection" do
    it "skips records emitted before GPS lock without failing the import" do
      track = parse_fit(build_fit(points: [
        { time: start },
        { time: start + 10 },
        { time: start + 60, lat: 45.0, lon: 6.0 },
        { time: start + 120, lat: 45.001, lon: 6.001 }
      ]))

      expect(track.points_count).to eq(2)
      expect(track.segments.first.first_point.time).to eq(start + 60)
    end

    it "skips records timestamped with device uptime rather than UTC" do
      bytes = FitBuilder.new
        .define(local: 0, global: 0, fields: [ [ 0, :enum ] ])
        .data(local: 0, values: [ 4 ])
        .define(local: 1, global: 20, fields: [ [ 253, :uint32 ], [ 0, :sint32 ], [ 1, :sint32 ] ])
        .data(local: 1, values: [ 1_000, FitBuilder.semicircles(45.0), FitBuilder.semicircles(6.0) ])
        .data(local: 1, values: [
          FitBuilder.fit_time(start), FitBuilder.semicircles(45.001), FitBuilder.semicircles(6.001)
        ])
        .data(local: 1, values: [
          FitBuilder.fit_time(start + 60), FitBuilder.semicircles(45.002), FitBuilder.semicircles(6.002)
        ])
        .to_s

      expect(parse_fit(bytes).points_count).to eq(2)
    end

    it "accepts repeated timestamps, which one-second resolution makes routine" do
      track = parse_fit(build_fit(points: [
        { time: start, lat: 45.0, lon: 6.0 },
        { time: start, lat: 45.001, lon: 6.001 },
        { time: start + 60, lat: 45.002, lon: 6.002 }
      ]))

      expect(track.points_count).to eq(3)
    end
  end

  describe "failures" do
    it "rejects a file that is not an Activity file" do
      bytes = build_fit(points: simple_fit_points(start:), file_type: :course)

      expect { parse_fit(bytes) }
        .to raise_error(Allure::Fit::UnsupportedFitError, /unsupported FIT file type: course/)
    end

    it "accepts an activity chained after a device file, as exports sometimes emit" do
      device = FitBuilder.new
        .define(local: 0, global: 0, fields: [ [ 0, :enum ] ])
        .data(local: 0, values: [ 1 ])
        .to_s
      activity = build_fit(points: simple_fit_points(start:), product_name: "Fenix 7")

      track = parse_fit(FitBuilder.chain(device, activity))

      expect(track.points_count).to eq(3)
      expect(track.creator).to eq("Fenix 7")
    end

    it "rejects a file with no file_id message, which the specification requires" do
      bytes = FitBuilder.new
        .define(local: 1, global: 20, fields: [ [ 253, :uint32 ], [ 0, :sint32 ], [ 1, :sint32 ] ])
        .data(local: 1, values: [ FitBuilder.fit_time(start), FitBuilder.semicircles(45.0), 0 ])
        .to_s

      expect { parse_fit(bytes) }.to raise_error(Allure::Fit::UnsupportedFitError, /no file_id/)
    end

    it "imports a file with no position at all as a positionless recording" do
      track = parse_fit(build_fit(points: [ { time: start, hr: 120 }, { time: start + 60, hr: 130 } ]))

      expect(track).not_to be_positioned
      expect(track.points_count).to eq(2)
      expect(track.segments.first.points.map(&:heart_rate)).to eq([ 120, 130 ])
    end

    it "imports a lone positioned record with the rest as a positionless recording" do
      bytes = build_fit(points: [ { time: start, lat: 45.0, lon: 6.0 }, { time: start + 60 } ])

      track = parse_fit(bytes)

      expect(track).not_to be_positioned
      expect(track.points_count).to eq(2)
      expect(track.segments.first.points.first).not_to be_positioned
    end

    it "keeps a recording positioned when sparse fixes span it, as Suunto writes them" do
      points = Array.new(600) do |second|
        point = { time: start + second, hr: 120 }
        second % 4 == 0 ? point.merge(lat: 45.0 + (second * 0.00001), lon: 6.0) : point
      end

      track = parse_fit(build_fit(points:))

      expect(track).to be_positioned
      expect(track.points_count).to eq(150)
      expect(track.segments.flat_map(&:points)).to all(be_positioned)
    end

    it "keeps a brief lock in a longer recording positionless" do
      points = Array.new(600) do |second|
        point = { time: start + second, hr: 120 }
        second < 60 ? point.merge(lat: 45.0, lon: 6.0) : point
      end

      track = parse_fit(build_fit(points:))

      expect(track).not_to be_positioned
      expect(track.points_count).to eq(600)
    end

    it "raises NoTrackError only when fewer than two timed records survive" do
      expect { parse_fit(build_fit(points: [ { time: start } ])) }
        .to raise_error(Allure::Gpx::NoTrackError)
    end

    it "drops an isolated backward record instead of failing the import" do
      bytes = build_fit(points: [
        { time: start, lat: 45.0, lon: 6.0 },
        { time: start + 120, lat: 45.001, lon: 6.001 },
        { time: start + 60, lat: 45.002, lon: 6.002 },
        { time: start + 180, lat: 45.003, lon: 6.003 }
      ])

      track = parse_fit(bytes)

      expect(track.segments.first.points.map(&:time)).to eq([ start, start + 120, start + 180 ])
      expect(track.points_count).to eq(3)
    end

    it "restarts from the corrected clock after a large backward jump" do
      bytes = build_fit(points: [
        { time: start + 90_000_000, lat: 45.0, lon: 6.0 },
        { time: start + 90_000_060, lat: 45.001, lon: 6.001 },
        { time: start, lat: 45.002, lon: 6.002 },
        { time: start + 60, lat: 45.003, lon: 6.003 },
        { time: start + 120, lat: 45.004, lon: 6.004 }
      ])

      track = parse_fit(bytes)

      expect(track.segments.first.points.map(&:time)).to eq([ start, start + 60, start + 120 ])
      expect(track.points_count).to eq(3)
    end

    it "refuses a fully reversed file because too little survives" do
      points = Array.new(8) { |index| { time: start + ((7 - index) * 60), lat: 45.0, lon: 6.0 } }
      bytes = build_fit(points:)

      expect { parse_fit(bytes) }.to raise_error(Allure::Gpx::NoTrackError)
    end

    it "raises TooManyPointsError above the shared point limit" do
      bytes = build_fit(points: simple_fit_points(start:))

      expect { parse_fit(bytes, max_points: 2) }
        .to raise_error(Allure::Gpx::TooManyPointsError, /more than 2 records/)
    end

    it "raises InvalidPointError for a latitude outside its range" do
      bytes = build_fit(points: [
        { time: start, lat: 120.0, lon: 6.0 },
        { time: start + 60, lat: 45.0, lon: 6.0 }
      ])

      expect { parse_fit(bytes) }.to raise_error(Allure::Gpx::InvalidPointError, /latitude out of range/)
    end

    it "surfaces container corruption as MalformedFitError" do
      bytes = build_fit(points: simple_fit_points(start:), corrupt_crc: true)

      expect { parse_fit(bytes) }.to raise_error(Allure::Fit::MalformedFitError)
    end
  end

  describe "activity signals" do
    it "emits exactly one signal so the detector's ambiguity guard is not triggered" do
      track = parse_fit(build_fit(points: simple_fit_points(start:), sport: 2, sub_sport: 8))

      expect(track.activity_signals.length).to eq(1)
      expect(track.activity_signals.first)
        .to have_attributes(source: :fit_sport, value: "mountain biking")
    end

    it "emits no signal for a sport outside the Allure catalog" do
      track = parse_fit(build_fit(points: simple_fit_points(start:), sport: 32))

      expect(track.activity_signals).to be_empty
    end

    it "emits no signal when the file carries no session message" do
      track = parse_fit(build_fit(points: simple_fit_points(start:)))

      expect(track.activity_signals).to be_empty
    end

    it "resolves to the expected seeded sport through ActivityDetector" do
      track = parse_fit(build_fit(points: simple_fit_points(start:), sport: 1, sub_sport: 3))

      expect(Allure::ActivityDetector.new.detect(track).sport_slug).to eq("trail")
    end

    it "records a commuting sub sport as a commute hint without changing the sport" do
      track = parse_fit(build_fit(points: simple_fit_points(start:), sport: 2, sub_sport: 48))

      expect(track.commute_hint).to be(true)
      expect(track.activity_signals.first.value).to eq("cycling")
      expect(Allure::ActivityDetector.new.detect(track).sport_slug).to eq("cycling")
    end

    it "does not set the commute hint for a road sub sport" do
      track = parse_fit(build_fit(points: simple_fit_points(start:), sport: 2, sub_sport: 7))

      expect(track.commute_hint).to be(false)
      expect(track.activity_signals.first.value).to eq("road cycling")
      expect(Allure::ActivityDetector.new.detect(track).sport_slug).to eq("cycling_road")
    end

    it "defaults the commute hint to false when the file carries no session" do
      expect(parse_fit(build_fit(points: simple_fit_points(start:))).commute_hint).to be(false)
    end
  end

  describe "big-endian files" do
    it "decodes an activity recorded by a big-endian device" do
      track = parse_fit(build_fit(points: simple_fit_points(start:), sport: 1, big_endian: true))

      expect(track.points_count).to eq(3)
      expect(track.segments.first.points.first.latitude).to be_within(1e-6).of(45.0640)
      expect(track.activity_signals.first.value).to eq("running")
    end
  end

  # The point of returning Allure::Gpx values rather than a FIT-specific
  # shape: every stage below the parser runs unchanged. If this block fails,
  # the format boundary has leaked.
  describe "compatibility with the shared metrics engine" do
    def analyze(track)
      Allure::Gpx::Analyzer.new(stopped_speed_threshold_km_h: 1.0, records_elevation: true).analyze(track)
    end

    it "produces metrics from a single-segment FIT track" do
      metrics = analyze(parse_fit(build_fit(points: simple_fit_points(start:))))

      expect(metrics.started_at).to eq(start)
      expect(metrics.duration).to eq(120)
      expect(metrics.points_count).to eq(3)
      expect(metrics.min_elevation).to eq(2000.0)
      expect(metrics.max_elevation).to eq(2020.0)
      # Smoothing leaves a three-point run unchanged: 2000*0.3 + 2010*0.4 +
      # 2020*0.3 = 2010, so the climb is the raw 20 m with no descent.
      expect(metrics.ascent).to eq(20.0)
      expect(metrics.descent).to eq(0.0)
      expect(metrics.distance).to be > 0
    end

    it "counts an inter-segment pause as duration but never as moving time" do
      points = (0..5).map { { time: start + (it * 60), lat: 45.0 + (it * 0.001), lon: 6.0 + (it * 0.001) } }
      metrics = analyze(parse_fit(build_fit(points:, stops: [ start + 180 ])))

      # Two 120 s segments plus the 60 s gap the stop_all event created.
      expect(metrics.segments.length).to eq(2)
      expect(metrics.duration).to eq(300)
      expect(metrics.moving_time).to be <= 240
      expect(metrics.pause_time).to eq(metrics.duration - metrics.moving_time)
    end

    it "serializes points into the persisted JSON contract" do
      metrics = analyze(parse_fit(build_fit(points: [
        { time: start, lat: 45.0, lon: 6.0, altitude: 100.0, hr: 140, cadence: 80, power: 200 },
        { time: start + 60, lat: 45.002, lon: 6.002, altitude: 110.0, hr: 150, cadence: 82, power: 210 }
      ])))
      point = metrics.segments.first.points.first

      expect(point).to include(
        Allure::Gpx::PointSerializer::KEY_TIME => 0,
        Allure::Gpx::PointSerializer::KEY_LATITUDE => 45.0,
        Allure::Gpx::PointSerializer::KEY_ELEVATION => 100.0,
        Allure::Gpx::PointSerializer::KEY_HEART_RATE => 140,
        Allure::Gpx::PointSerializer::KEY_CADENCE => 80,
        Allure::Gpx::PointSerializer::KEY_POWER => 200
      )
    end
  end
end
