# frozen_string_literal: true

require "rails_helper"

RSpec.describe "FIT conformance corpus" do
  CORPUS_ROOT = Rails.root.join("references_apps/fit-test-files").freeze
  ACTIVITY_FILES = Dir[CORPUS_ROOT.join("Activity/**/*.fit").to_s].sort.freeze
  ALL_MESSAGES_FILE = CORPUS_ROOT.join("AllFitMessageTypes.fit").freeze

  SPORT_SAMPLES = {
    "Activity/2026/Activity_20260215_001_003_Running_Trail_Fenix7x_a790a6293770eda5fbd090ebfe8203b6.fit" => {
      alias: "trail running",
      slug: "trail"
    },
    "Activity/2026/Activity_20260114_002_008_Cycling_Mountain_EdgeMtb_da6a5e2deec8f950a983c0dd81ab28c0.fit" => {
      alias: "mountain biking",
      slug: "mountain_biking"
    },
    "Activity/2026/Activity_20260217_002_007_Cycling_Road_Edge1050_7941c9691ae19ad740a6673e95ea837d.fit" => {
      alias: "road cycling",
      slug: "cycling_road"
    },
    "Activity/2024/Activity_20240831_005_018_Swimming_Open-Water_Fenix3Hr_3fd1baf9c1fda907fcd2078dfa0df3ad.fit" => {
      alias: "open water swimming",
      slug: "open_water_swimming"
    },
    "Activity/2023/Activity_20230610_017_003_Hiking_Trail_Suunto-Vertical_d149673ba8d0667bef7a9fb68d91925d.fit" => {
      alias: "hiking",
      slug: "hiking"
    }
  }.freeze

  # Files a device exported without ever reaching a fix: they are imported as
  # positionless recordings (PLAN_NO_GPS.md §3), analysed from the device's
  # own distance and speed. Diving stays out of the list: those records carry
  # no usable timestamp and the file is still rejected.
  POSITIONLESS_MARKERS = %w[Treadmill Yoga Strength-Training Breathing].freeze
  NO_TIMED_RECORDS_MARKERS = %w[Diving].freeze
  # Outdoor recordings whose devices write a fix only on a minority of their
  # one-second records; they must keep their route (PLAN_NO_GPS.md §3.1).
  SPARSE_FIX_SAMPLES = %w[
    Activity/2023/Activity_20230610_017_003_Hiking_Trail_Suunto-Vertical_3139dfeee3252b9c7d50729f13b51d04.fit
    Activity/2020/Activity_20201023_002_008_Cycling_Mountain_Suunto-Spartan-Sport-Wrist-HR-Baro_405f58c2aced451bf4bfa97d81f7b7c0.fit
    Activity/2025/Activity_20250929_001_003_Running_Trail_COROS-Wearables_09bd6787a65a68ae5206775db80cc762.fit
  ].freeze
  METRICS = { heart_rate: "hr", cadence: "cad", power: "pw" }.freeze

  def parse_file(path)
    File.open(path, "rb") { |io| Allure::Fit::Parser.new.parse(io) }
  end

  def parse_with_error(path)
    [ parse_file(path), nil ]
  rescue StandardError => error
    [ nil, error ]
  end

  if !CORPUS_ROOT.directory?
    it "is optional when the local corpus has not been fetched" do
      skip "run script/fetch-fit-corpus to enable real-file conformance tests"
    end
  else
    it "contains real activity files" do
      expect(ACTIVITY_FILES).not_to be_empty
    end

    ACTIVITY_FILES.each do |path|
      relative = path.to_s.delete_prefix("#{CORPUS_ROOT}/")

      it "handles #{relative}" do
        track, error = parse_with_error(path)

        if error
          allowed = error.is_a?(Allure::Fit::Error) || error.is_a?(Allure::Gpx::Error)
          expect(allowed).to be(true), "#{relative} raised #{error.class}: #{error.message}"
        else
          points = track.segments.flat_map(&:points)

          expect(track).to be_a(Allure::Gpx::Track)
          expect(track.segments).not_to be_empty
          expect(points.length).to be >= 2
          expect(track.points_count).to eq(points.length)
          expect(points.map(&:time)).to eq(points.map(&:time).sort)
          # A real file is either fully positioned or fully positionless
          # (PLAN_NO_GPS.md §3.1); a mix would mean the classification leaked
          # into the segments.
          if track.positioned?
            expect(points).to all(be_positioned)
            expect(points.all? { |point| point.latitude.between?(-90.0, 90.0) }).to be(true)
            expect(points.all? { |point| point.longitude.between?(-180.0, 180.0) }).to be(true)
          else
            expect(points).to all(satisfy { |point| !point.positioned? })
          end
          expect(track.calories).to be >= 0 if track.calories
          expect(track.activity_signals.length).to be <= 1
          expect(track.activity_signals.all? { |signal| signal.source == :fit_sport }).to be(true)

          metrics = Allure::Gpx::Analyzer.new(stopped_speed_threshold_km_h: 1.0).analyze(track)
          expect(metrics.started_at).to be_a(Time)
          expect([ metrics.duration, metrics.moving_time, metrics.pause_time, metrics.distance, metrics.ascent, metrics.descent ]).to all(be >= 0)
          expect([ metrics.average_speed, metrics.max_speed ].compact).to all(be >= 0)
        end
      end
    end

    POSITIONLESS_MARKERS.each do |marker|
      it "imports a real #{marker} activity as a positionless recording" do
        path = ACTIVITY_FILES.find { |candidate| File.basename(candidate).include?(marker) }

        expect(path).to be_present
        track = parse_file(path)
        expect(track).not_to be_positioned

        metrics = Allure::Gpx::Analyzer.new(stopped_speed_threshold_km_h: 1.0).analyze(track)
        expect(metrics.bounds).to be_nil
        expect(metrics.start_point).to be_nil
        expect(metrics.distance).to be >= 0
        expect(metrics.duration).to be >= 0
      end
    end

    SPARSE_FIX_SAMPLES.each do |relative|
      it "keeps the route of sparse-fix recording #{relative}" do
        path = CORPUS_ROOT.join(relative)
        expect(File.file?(path)).to be(true), "missing corpus sample #{relative}"

        metrics = Allure::Gpx::Analyzer.new(stopped_speed_threshold_km_h: 1.0).analyze(parse_file(path))
        expect(metrics.start_point).to be_present
        expect(metrics.bounds).to be_present
      end
    end

    NO_TIMED_RECORDS_MARKERS.each do |marker|
      it "still rejects a real #{marker} activity with no timed record" do
        path = ACTIVITY_FILES.find { |candidate| File.basename(candidate).include?(marker) }

        expect(path).to be_present
        expect { parse_file(path) }.to raise_error(Allure::Gpx::NoTrackError)
      end
    end

    SPORT_SAMPLES.each do |relative, expected|
      it "maps the external sport identifiers in #{relative}" do
        path = CORPUS_ROOT.join(relative)
        expect(File.file?(path)).to be(true), "missing corpus sample #{relative}"

        track = parse_file(path)
        expect(track.activity_signals.map(&:value)).to eq([ expected.fetch(:alias) ])
        expect(Allure::ActivityDetector.new.detect(track).sport_slug).to eq(expected.fetch(:slug))
      end
    end

    it "preserves real heart rate, cadence, and power records through analysis" do
      tracks = {}

      ACTIVITY_FILES.each do |path|
        track, error = parse_with_error(path)
        next if error

        points = track.segments.flat_map(&:points)
        METRICS.each_key do |metric|
          tracks[metric] ||= track if points.any? { |point| point.public_send(metric).present? }
        end
        break if tracks.length == METRICS.length
      end

      expect(tracks.keys).to contain_exactly(*METRICS.keys)
      METRICS.each do |metric, serialized_key|
        track = tracks.fetch(metric)
        metrics = Allure::Gpx::Analyzer.new(stopped_speed_threshold_km_h: 1.0).analyze(track)
        aggregate = metrics.segments.flat_map { |segment| [ segment.public_send("average_#{metric}"), segment.public_send("max_#{metric}") ] }.compact
        serialized = metrics.segments.flat_map(&:points)

        expect(aggregate).not_to be_empty
        expect(serialized.any? { |point| point.key?(serialized_key) }).to be(true)
      end
    end

    it "traverses AllFitMessageTypes without an unexpected exception" do
      expect(File.file?(ALL_MESSAGES_FILE)).to be(true)
      _track, error = parse_with_error(ALL_MESSAGES_FILE)

      if error
        allowed = error.is_a?(Allure::Fit::Error) || error.is_a?(Allure::Gpx::Error)
        expect(allowed).to be(true), "AllFitMessageTypes raised #{error.class}: #{error.message}"
      end
    end
  end
end
