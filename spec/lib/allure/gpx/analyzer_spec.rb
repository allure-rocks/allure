# frozen_string_literal: true

require "rails_helper"

# Expected values below are independently derived from the equirectangular /
# haversine / outlier / elevation-filter / threshold formulas documented in
# docs/dev/WORKOUT.md, not by running this analyzer and recording its
# output.
RSpec.describe Allure::Gpx::Analyzer do
  describe "galibier: normal timed 3D route" do
    subject(:metrics) { analyze_gpx_fixture("galibier") }

    it "computes 3D distance, duration, and moving time" do
      expect(metrics.distance).to be_within(0.001).of(483.11864482371004)
      expect(metrics.duration).to eq(180)
      expect(metrics.moving_time).to eq(180)
      expect(metrics.pause_time).to eq(0)
    end

    it "computes average and filtered maximum speed" do
      expect(metrics.average_speed).to be_within(0.0001).of(2.6839924712428336)
      expect(metrics.max_speed).to be_within(0.0001).of(2.8581590430126007)
      expect(metrics.average_pace).to eq(373)
      expect(metrics.best_pace).to eq(350)
    end

    it "computes a faster grade-adjusted pace for the uphill route" do
      expect(metrics.grade_adjusted_pace).to be_a(Integer)
      expect(metrics.grade_adjusted_pace).to be < metrics.average_pace
      expect(metrics.segments.first.grade_adjusted_pace).to eq(metrics.grade_adjusted_pace)
    end

    it "counts the coarse profile deltas with the threshold and filters min/max" do
      # The four samples are farther apart than the filter windows, so the
      # canonical profile is the raw profile and the accumulator counts the
      # whole excursions: +50, +70, -20.
      expect(metrics.ascent).to be_within(0.001).of(120.0)
      expect(metrics.descent).to be_within(0.001).of(20.0)
      expect(metrics.min_elevation).to eq(2000.0)
      expect(metrics.max_elevation).to eq(2120.0)
    end

    it "reports bounds and start point in [lat, lon] / [lon, lat] order" do
      expect(metrics.bounds).to eq([ 45.0640, 6.4077, 45.0670, 6.4117 ])
      expect(metrics.start_point).to eq([ 6.4077, 45.0640 ])
    end
  end

  describe "multi_segment: segment ordering and pause gap" do
    subject(:metrics) { analyze_gpx_fixture("multi_segment") }

    it "sums segment durations plus the positive inter-segment gap" do
      expect(metrics.duration).to eq(840)
      expect(metrics.moving_time).to eq(240)
      expect(metrics.pause_time).to eq(600)
    end

    it "sums distance and ascent across segments without bridging them" do
      expect(metrics.distance).to be_within(0.001).of(445.58326254239233)
      expect(metrics.ascent).to be_within(0.001).of(16.0)
    end

    it "produces one TrackSegment-ready metrics object per trkseg" do
      expect(metrics.segments.length).to eq(2)
      expect(metrics.segments.map(&:duration)).to eq([ 120, 120 ])
    end
  end

  describe "multiple_tracks: all tracks imported in document order" do
    subject(:metrics) { analyze_gpx_fixture("multiple_tracks") }

    it "flattens segments from every trk in document order" do
      expect(metrics.segments.length).to eq(2)
      expect(metrics.points_count).to eq(4)
    end

    it "treats the gap between tracks like any other inter-segment gap" do
      expect(metrics.duration).to eq(180)
      expect(metrics.moving_time).to eq(120)
      expect(metrics.pause_time).to eq(60)
    end
  end

  describe "no_elevation: 2D fallback" do
    subject(:metrics) { analyze_gpx_fixture("no_elevation") }

    it "falls back to 2D distance and reports no elevation" do
      expect(metrics.distance).to be_within(0.001).of(222.63898158681923)
      expect(metrics.ascent).to eq(0.0)
      expect(metrics.descent).to eq(0.0)
      expect(metrics.min_elevation).to be_nil
      expect(metrics.max_elevation).to be_nil
    end

    it "omits elevation from serialized points" do
      point = metrics.segments.first.points.first
      expect(point).not_to have_key("ele")
    end

    it "reports no grade-adjusted pace" do
      expect(metrics.grade_adjusted_pace).to be_nil
      expect(metrics.segments.first.grade_adjusted_pace).to be_nil
    end
  end

  describe "sea_level: elevation 0.0 is valid" do
    subject(:metrics) { analyze_gpx_fixture("sea_level") }

    it "treats 0.0 as present, not missing" do
      expect(metrics.min_elevation).to eq(0.0)
      expect(metrics.max_elevation).to eq(0.0)
      expect(metrics.ascent).to eq(0.0)
      expect(metrics.descent).to eq(0.0)
    end

    it "includes the 0.0 elevation in serialized points" do
      point = metrics.segments.first.points.first
      expect(point.fetch("ele")).to eq(0.0)
    end
  end

  describe "zero_placeholders: a partial profile has no elevation" do
    subject(:metrics) { analyze_gpx_fixture("zero_placeholders") }

    it "reports no elevation at all" do
      expect(metrics.min_elevation).to be_nil
      expect(metrics.max_elevation).to be_nil
      expect(metrics.ascent).to eq(0.0)
      expect(metrics.descent).to eq(0.0)
      expect(metrics.elevation_filter).to be_nil
    end

    it "omits elevation from the serialized points" do
      expect(metrics.segments.first.points.map { |point| point["ele"] }).to all(be_nil)
    end
  end

  describe "stationary: zero-distance intervals and pause calculation" do
    subject(:metrics) { analyze_gpx_fixture("stationary") }

    it "excludes the zero-distance interval from moving time" do
      expect(metrics.duration).to eq(120)
      expect(metrics.moving_time).to eq(60)
      expect(metrics.pause_time).to eq(60)
    end

    it "omits point speed where no adjacent interval has positive time and distance" do
      points = metrics.segments.first.points
      # The stationary interval contributes speed 0.0 to both of its
      # endpoints' means alongside the moving interval, so only the point
      # with no valid interval at all would omit "v"; here every point has
      # at least one adjacent interval, all with defined (possibly zero)
      # speed.
      expect(points.map { |point| point.key?("v") }).to eq([ true, true, true ])
    end
  end

  describe "positionless: indoor recordings measured from the device" do
    let(:start) { Time.zone.parse("2026-06-01 08:00:00 UTC") }

    # A trainer session: cumulative device distance and speed, one 30 s
    # standstill in the middle, no coordinates anywhere (docs/dev/NO-GPS.md).
    # Speeds are consistent with the distance steps so the fixture carries no
    # anomaly of its own.
    subject(:metrics) do
      points = [
        Allure::Gpx::Point.new(time: start, distance: 0.0, speed: 6.0, heart_rate: 120, power: 190),
        Allure::Gpx::Point.new(time: start + 60, distance: 360.0, speed: 6.0, heart_rate: 130, power: 210),
        Allure::Gpx::Point.new(time: start + 120, distance: 360.0, speed: 0.0, heart_rate: 125, power: 120),
        Allure::Gpx::Point.new(time: start + 180, distance: 600.0, speed: 5.0, heart_rate: 135, power: 230)
      ]
      described_class.new(stopped_speed_threshold_km_h: 1.0).analyze(
        Allure::Gpx::Track.new(source_max_speed: 6.0, segments: [ Allure::Gpx::Segment.new(points:) ])
      )
    end

    it "measures distance from the device's cumulative record" do
      expect(metrics.distance).to eq(600.0)
      expect(metrics.segments.first.distance).to eq(600.0)
    end

    it "keeps the standstill out of moving time" do
      expect(metrics.duration).to eq(180)
      expect(metrics.moving_time).to eq(120)
      expect(metrics.pause_time).to eq(60)
    end

    it "derives average and maximum speed from the device's own readings" do
      expect(metrics.average_speed).to be_within(0.0001).of(600.0 / 120)
      expect(metrics.max_speed).to be_within(0.0001).of(6.0)
      expect(metrics.best_pace).to eq((1000.0 / 6.0).round)
    end

    it "carries no bounds, no start point, no ascent and no elevation" do
      expect(metrics.bounds).to be_nil
      expect(metrics.start_point).to be_nil
      expect(metrics.ascent).to eq(0.0)
      expect(metrics.descent).to eq(0.0)
      expect(metrics.min_elevation).to be_nil
      expect(metrics.max_elevation).to be_nil
      expect(metrics.elevation_filter).to be_nil
      expect(metrics.grade_adjusted_pace).to be_nil
    end

    it "serializes points without coordinates, with the recorded readings" do
      points = metrics.segments.first.points

      expect(points.map { |point| point.key?("lat") || point.key?("lon") }).to all(be(false))
      expect(points.map { |point| point["d"] }).to eq([ 0.0, 360.0, 360.0, 600.0 ])
      expect(points.map { |point| point["v"] }).to eq([ 6.0, 6.0, nil, 5.0 ])
      expect(points.map { |point| point["t"] }).to eq([ 0, 60, 120, 180 ])
    end

    it "keeps heart rate and power, and reports no coordinates" do
      expect(metrics.segments.first.coordinates).to eq([])
      expect(metrics.average_heart_rate).to eq(128)
      expect(metrics.average_power).to eq(188)
    end

    it "flags no anomaly and no contested figure on a clean recording" do
      # No coordinate-derived figure can be contested here, so the payload is
      # empty rather than carrying an empty findings list.
      expect(metrics.anomalies).to eq({})
    end
  end

  describe "positionless: duration-only sessions" do
    let(:start) { Time.zone.parse("2026-06-01 08:00:00 UTC") }

    it "treats the timer as moving when the file records neither distance nor speed" do
      points = [
        Allure::Gpx::Point.new(time: start, heart_rate: 100),
        Allure::Gpx::Point.new(time: start + 120, heart_rate: 110)
      ]
      metrics = described_class.new(stopped_speed_threshold_km_h: 2.0).analyze(
        Allure::Gpx::Track.new(segments: [ Allure::Gpx::Segment.new(points:) ])
      )

      expect(metrics.distance).to eq(0.0)
      expect(metrics.duration).to eq(120)
      expect(metrics.moving_time).to eq(120)
      expect(metrics.pause_time).to eq(0)
      expect(metrics.average_speed).to eq(0.0)
      expect(metrics.max_speed).to be_nil
      expect(metrics.segments.first.points.map { |point| point["v"] }).to eq([ nil, nil ])
    end

    it "counts a standstill the device recorded through distance alone as a pause" do
      points = [
        Allure::Gpx::Point.new(time: start, distance: 0.0),
        Allure::Gpx::Point.new(time: start + 100, distance: 0.0)
      ]
      metrics = described_class.new(stopped_speed_threshold_km_h: 2.0).analyze(
        Allure::Gpx::Track.new(segments: [ Allure::Gpx::Segment.new(points:) ])
      )

      expect(metrics.distance).to eq(0.0)
      expect(metrics.moving_time).to eq(0)
      expect(metrics.pause_time).to eq(100)
    end

    it "integrates distance from the device speed when the file has no cumulative distance" do
      points = [
        Allure::Gpx::Point.new(time: start, speed: 5.0),
        Allure::Gpx::Point.new(time: start + 60, speed: 5.0),
        Allure::Gpx::Point.new(time: start + 90, speed: 5.0)
      ]
      metrics = described_class.new(stopped_speed_threshold_km_h: 1.0).analyze(
        Allure::Gpx::Track.new(segments: [ Allure::Gpx::Segment.new(points:) ])
      )

      expect(metrics.distance).to eq(450.0)
      expect(metrics.moving_time).to eq(90)
      expect(metrics.average_speed).to eq(5.0)
    end

    it "treats a frozen cumulative distance as a standstill even under a live speed reading" do
      points = [
        Allure::Gpx::Point.new(time: start, distance: 0.0, speed: 2.0),
        Allure::Gpx::Point.new(time: start + 60, distance: 0.0, speed: 2.0)
      ]
      metrics = described_class.new(stopped_speed_threshold_km_h: 1.0).analyze(
        Allure::Gpx::Track.new(segments: [ Allure::Gpx::Segment.new(points:) ])
      )

      expect(metrics.distance).to eq(0.0)
      expect(metrics.moving_time).to eq(0)
    end

    it "rejects a backward cumulative distance step" do
      points = [
        Allure::Gpx::Point.new(time: start, distance: 1_000.0),
        Allure::Gpx::Point.new(time: start + 60, distance: 900.0)
      ]
      metrics = described_class.new(stopped_speed_threshold_km_h: 1.0).analyze(
        Allure::Gpx::Track.new(segments: [ Allure::Gpx::Segment.new(points:) ])
      )

      expect(metrics.distance).to eq(0.0)
    end
  end

  describe "second-resolution timestamps" do
    # A GPX export rounds timestamps to the second, so consecutive points can
    # repeat a timestamp over real movement. That path length still belongs to
    # the workout; only moving time and speed need positive time.
    it "keeps the distance of a zero-time interval without counting moving time" do
      started_at = Time.zone.parse("2026-06-01 08:00:00 UTC")
      points = [
        Allure::Gpx::Point.new(time: started_at, latitude: 45.0, longitude: 6.0),
        Allure::Gpx::Point.new(time: started_at + 10, latitude: 45.001, longitude: 6.0),
        Allure::Gpx::Point.new(time: started_at + 10, latitude: 45.002, longitude: 6.0),
        Allure::Gpx::Point.new(time: started_at + 20, latitude: 45.003, longitude: 6.0)
      ]
      track = Allure::Gpx::Track.new(segments: [ Allure::Gpx::Segment.new(points:) ])

      metrics = described_class.new(stopped_speed_threshold_km_h: 0.5).analyze(track)

      expect(metrics.distance).to be_within(0.001).of(333.958472379820705)
      expect(metrics.duration).to eq(20)
      expect(metrics.moving_time).to eq(20)
      expect(metrics.pause_time).to eq(0)
      expect(metrics.segments.first.points.last["d"]).to eq(334.0)
    end
  end

  describe "speed_spike: GPS detour regression" do
    subject(:metrics) { analyze_gpx_fixture("speed_spike") }

    it "removes the out-and-back GPS detour from the total distance" do
      expect(metrics.distance).to be_within(0.001).of(35.06563959993787)
      expect(metrics.points_count).to eq(7)
    end

    it "excludes the out-and-back GPS detour from maximum speed" do
      expect(metrics.max_speed).to be_within(0.0001).of(5.00937708570541)
      expect(metrics.best_pace).to eq(200)
    end

    it "keeps a genuine out-and-back recorded over a plausible duration" do
      started_at = Time.zone.parse("2026-06-01 08:00:00 UTC")
      points = [
        Allure::Gpx::Point.new(time: started_at, latitude: 45.0, longitude: 6.0),
        Allure::Gpx::Point.new(time: started_at + 60, latitude: 45.001, longitude: 6.0),
        Allure::Gpx::Point.new(time: started_at + 120, latitude: 45.0, longitude: 6.0)
      ]
      track = Allure::Gpx::Track.new(segments: [ Allure::Gpx::Segment.new(points:) ])

      analyzed = described_class.new(stopped_speed_threshold_km_h: 1.0).analyze(track)

      expect(analyzed.max_speed).to be_within(0.001).of(1.855)
    end
  end


  describe "GPS noise handling" do
    it "classifies a noisy 1 Hz profile as GPS and recovers the true climb" do
      started_at = Time.zone.parse("2026-06-01 08:00:00 UTC")
      points = 300.times.map do |index|
        Allure::Gpx::Point.new(
          time: started_at + index,
          latitude: 45.0 + (index * 0.00002695),
          longitude: 6.0,
          elevation: 100.0 + (index * 0.15) + (index.even? ? 0.8 : -0.8)
        )
      end
      track = Allure::Gpx::Track.new(segments: [ Allure::Gpx::Segment.new(points:) ])

      metrics = described_class.new(stopped_speed_threshold_km_h: 0.5).analyze(track)

      # The true ramp gains 44.85 m; the alternating ±0.8 m noise is removed by
      # the distance-window average and the threshold accumulator.
      expect(metrics.elevation_filter).to eq(:gps)
      expect(metrics.ascent).to be_within(1.0).of(42.1)
      expect(metrics.descent).to eq(0.0)
      expect(metrics.distance).to be_within(0.01).of(898.1802619197705)
    end

    it "trims a cold-start artifact from distance and speed" do
      started_at = Time.zone.parse("2026-06-01 08:00:00 UTC")
      points = [ Allure::Gpx::Point.new(time: started_at, latitude: 45.0, longitude: 6.0) ]
      latitude = 45.0
      8.times do |index|
        latitude += 8.0 / 111_319.49
        points << Allure::Gpx::Point.new(time: started_at + index + 1, latitude:, longitude: 6.0)
      end
      100.times do |index|
        latitude += 1.2 / 111_319.49
        points << Allure::Gpx::Point.new(time: started_at + 9 + index, latitude:, longitude: 6.0)
      end
      track = Allure::Gpx::Track.new(segments: [ Allure::Gpx::Segment.new(points:) ])

      metrics = described_class.new(stopped_speed_threshold_km_h: 0.5).analyze(track)

      expect(metrics.points_count).to eq(101)
      expect(metrics.started_at).to eq(started_at + 8)
      expect(metrics.distance).to be_within(0.001).of(120.0)
      expect(metrics.max_speed).to be_within(0.001).of(1.2)
    end
  end

  describe "source-reported maximum speed" do
    it "takes precedence at workout level without replacing segment estimates" do
      started_at = Time.zone.parse("2026-06-01 08:00:00 UTC")
      points = [
        Allure::Gpx::Point.new(time: started_at, latitude: 45.0, longitude: 6.0),
        Allure::Gpx::Point.new(time: started_at + 3, latitude: 45.0001, longitude: 6.0)
      ]
      track = Allure::Gpx::Track.new(
        segments: [ Allure::Gpx::Segment.new(points:) ],
        source_max_speed: 20.0
      )

      metrics = described_class.new(stopped_speed_threshold_km_h: 1.0).analyze(track)

      expect(metrics.max_speed).to eq(20.0)
      expect(metrics.best_pace).to eq(50)
      expect(metrics.segments.first.max_speed).not_to eq(20.0)
    end
  end

  describe "antimeridian: shortest longitude delta" do
    subject(:metrics) { analyze_gpx_fixture("antimeridian") }

    it "computes the short great-circle distance instead of wrapping the long way around" do
      expect(metrics.distance).to be_within(0.001).of(333.95847238141533)
    end

    it "records the raw encountered longitudes in bounds" do
      expect(metrics.bounds).to eq([ 0.0, -179.9990, 0.0, 179.9990 ])
      expect(metrics.start_point).to eq([ 179.9990, 0.0 ])
    end
  end

  describe "with_extensions: HR, cadence, and power" do
    subject(:metrics) { analyze_gpx_fixture("with_extensions") }

    it "computes physiological averages and maxima from present values only" do
      expect(metrics.average_heart_rate).to eq(150)
      expect(metrics.max_heart_rate).to eq(160)
      expect(metrics.average_cadence).to eq(82)
      expect(metrics.max_cadence).to eq(84)
      expect(metrics.average_power).to eq(210)
      expect(metrics.max_power).to eq(220)
    end

    it "passes through track-level calories" do
      expect(metrics.calories).to eq(350)
    end

    it "includes hr/cad/pw in serialized points" do
      point = metrics.segments.first.points.first
      expect(point.values_at("hr", "cad", "pw")).to eq([ 140, 80, 200 ])
    end

    it "treats zero heart rate as missing in averages, maxima, and serialized points" do
      started_at = Time.zone.parse("2026-06-01 08:00:00 UTC")
      points = [
        Allure::Gpx::Point.new(time: started_at, latitude: 45.0, longitude: 6.0, heart_rate: 0, cadence: 0, power: 0),
        Allure::Gpx::Point.new(time: started_at + 60, latitude: 45.001, longitude: 6.0, heart_rate: 120, cadence: 80, power: 200),
        Allure::Gpx::Point.new(time: started_at + 120, latitude: 45.002, longitude: 6.0, heart_rate: 140, cadence: 82, power: 210)
      ]
      track = Allure::Gpx::Track.new(segments: [ Allure::Gpx::Segment.new(points:) ])

      metrics = described_class.new(stopped_speed_threshold_km_h: 1.0).analyze(track)

      expect(metrics.average_heart_rate).to eq(130)
      expect(metrics.max_heart_rate).to eq(140)
      expect(metrics.average_cadence).to eq(54)
      expect(metrics.segments.first.points.first).not_to have_key("hr")
      expect(metrics.segments.first.points.first["cad"]).to eq(0)
    end

    it "reports nil heart rate when every sample is a dropout" do
      started_at = Time.zone.parse("2026-06-01 08:00:00 UTC")
      points = [
        Allure::Gpx::Point.new(time: started_at, latitude: 45.0, longitude: 6.0, heart_rate: 0),
        Allure::Gpx::Point.new(time: started_at + 60, latitude: 45.001, longitude: 6.0, heart_rate: 0)
      ]
      track = Allure::Gpx::Track.new(segments: [ Allure::Gpx::Segment.new(points:) ])

      metrics = described_class.new(stopped_speed_threshold_km_h: 1.0).analyze(track)

      expect(metrics.average_heart_rate).to be_nil
      expect(metrics.max_heart_rate).to be_nil
    end
  end

  describe "one_point_segments: invalid segments ignored" do
    subject(:metrics) { analyze_gpx_fixture("one_point_segments") }

    it "analyzes only the surviving two-point segment" do
      expect(metrics.segments.length).to eq(1)
      expect(metrics.points_count).to eq(2)
      expect(metrics.distance).to be_within(0.001).of(111.43172362748439)
    end
  end

  describe "moving/stopped threshold boundary" do
    it "treats speed exactly at the threshold as stopped" do
      track = parse_gpx_fixture("stationary")
      # The moving interval covers ~111.32m in 60s, i.e. ~6.68 km/h.
      metrics = described_class.new(stopped_speed_threshold_km_h: 6.679169447580848, records_elevation: true).analyze(track)
      expect(metrics.moving_time).to eq(0)
      expect(metrics.pause_time).to eq(120)
    end
  end

  describe "records_elevation: false" do
    it "discards elevation metrics and uses 2D distance even when the file supplies elevation" do
      track = parse_gpx_fixture("galibier")
      metrics = described_class.new(stopped_speed_threshold_km_h: 0.5, records_elevation: false).analyze(track)

      expect(metrics.ascent).to eq(0.0)
      expect(metrics.descent).to eq(0.0)
      expect(metrics.min_elevation).to be_nil
      expect(metrics.max_elevation).to be_nil
      expect(metrics.distance).to be_within(0.001).of(458.80752077267624)
      expect(metrics.elevation_filter).to be_nil
      expect(metrics.segments.first.points.first).not_to have_key("ele")
      expect(metrics.grade_adjusted_pace).to be_nil
    end
  end

  describe "grade_adjusted_pace: false" do
    it "leaves the metric nil even with a full elevation profile" do
      track = parse_gpx_fixture("galibier")
      metrics = described_class.new(stopped_speed_threshold_km_h: 0.5, grade_adjusted_pace: false).analyze(track)

      expect(metrics.grade_adjusted_pace).to be_nil
      expect(metrics.segments.first.grade_adjusted_pace).to be_nil
    end
  end

  describe "forced elevation filter" do
    def synthetic_track(elevations)
      points = elevations.each_with_index.map do |elevation, index|
        Allure::Gpx::Point.new(
          time: index * 60,
          latitude: 45.0,
          longitude: 6.0 + (index * 0.001),
          elevation:
        )
      end
      Allure::Gpx::Track.new(segments: [ Allure::Gpx::Segment.new(points:) ])
    end

    it "uses the forced class for the ascent threshold" do
      two_metres = synthetic_track([ 100.0, 102.0, 100.0 ])
      six_metres = synthetic_track([ 100.0, 106.0, 100.0 ])

      auto = described_class.new(stopped_speed_threshold_km_h: 0.5).analyze(two_metres)
      gps = described_class.new(stopped_speed_threshold_km_h: 0.5, elevation_filter: :gps).analyze(six_metres)
      dem = described_class.new(stopped_speed_threshold_km_h: 0.5, elevation_filter: :dem).analyze(six_metres)

      expect(auto.elevation_filter).to eq(:barometric)
      expect(auto.ascent).to eq(2.0)
      expect(gps.elevation_filter).to eq(:gps)
      expect(gps.ascent).to eq(6.0)
      expect(dem.elevation_filter).to eq(:dem)
      expect(dem.ascent).to eq(0.0)
    end

    it "keeps the profile unset without a valid elevation" do
      metrics = analyze_gpx_fixture("no_elevation", elevation_filter: :gps)

      expect(metrics.elevation_filter).to be_nil
    end
  end

  describe "duration and gap validation" do
    it "raises when a later document-order segment starts before the previous one finished" do
      track = Allure::Gpx::Track.new(
        segments: [
          Allure::Gpx::Segment.new(points: [
            Allure::Gpx::Point.new(time: Time.zone.parse("2026-01-01T00:01:00Z"), latitude: 45.0, longitude: 6.0),
            Allure::Gpx::Point.new(time: Time.zone.parse("2026-01-01T00:02:00Z"), latitude: 45.001, longitude: 6.0)
          ]),
          Allure::Gpx::Segment.new(points: [
            Allure::Gpx::Point.new(time: Time.zone.parse("2026-01-01T00:00:00Z"), latitude: 45.002, longitude: 6.0),
            Allure::Gpx::Point.new(time: Time.zone.parse("2026-01-01T00:00:30Z"), latitude: 45.003, longitude: 6.0)
          ])
        ]
      )

      expect { described_class.new(stopped_speed_threshold_km_h: 0.5).analyze(track) }
        .to raise_error(Allure::Gpx::NonMonotonicTimestampError)
    end
  end

  describe "a half-clean, half-zigzag recording" do
    it "rejects the zigzag without rescanning the track" do
      started_at = Time.zone.parse("2026-06-01T08:00:00Z")
      metres = 111_319.49
      clean = (0...25_000).map do |index|
        Allure::Gpx::Point.new(time: started_at + index, latitude: 45.0 + (index * 3.0 / metres), longitude: 6.0)
      end
      base = 45.0 + (75_000.0 / metres)
      zigzag = (0...25_000).map do |index|
        latitude = index.even? ? base : base + (111.0 / metres)
        Allure::Gpx::Point.new(time: started_at + 25_000 + index, latitude:, longitude: 6.0)
      end
      track = Allure::Gpx::Track.new(segments: [ Allure::Gpx::Segment.new(points: clean + zigzag) ])

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      metrics = described_class.new(stopped_speed_threshold_km_h: 1.0).analyze(track)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      expect(metrics.distance).to be_within(500.0).of(75_000.0)
      expect(elapsed).to be < 30.0
    end
  end
end
