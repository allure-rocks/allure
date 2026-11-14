# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workouts::Reanalyzer do
  let(:user) { create(:user) }
  let(:sport) { catalog_sport("cycling") }

  def imported_workout(time_shift: nil)
    upload = ActionDispatch::Http::UploadedFile.new(
      tempfile: File.open(Rails.root.join("spec/fixtures/gpx/galibier.gpx")),
      filename: "galibier.gpx",
      type: "application/gpx+xml"
    )
    Workouts::Importer.new(user:, sport:, uploaded_file: upload, time_shift:).call!
  end

  def terrain_workout
    upload = ActionDispatch::Http::UploadedFile.new(
      tempfile: File.open(Rails.root.join("spec/fixtures/gpx/no_elevation.gpx")),
      filename: "no_elevation.gpx",
      type: "application/gpx+xml"
    )
    Workouts::Importer.new(user:, sport:, uploaded_file: upload).call!
  end

  # Distances come from the same geometry the reanalysis recomputes, so the
  # cached profile covers every point exactly as the enricher stores it.
  def with_terrain_profile(workout, elevations: [ 1000.0, 1100.0, 1200.0 ])
    segments = Workouts::OriginalTrack.new(workout:).call.segments
    distances = Allure::Elevation::TrackGeometry.cumulative_distances(segments).first
    samples = distances.each_with_index.map do |distance, index|
      { "distance" => distance, "latitude" => 45.0, "longitude" => 6.4, "elevation" => elevations[index] }
    end
    create(:workout_elevation, workout:, samples:)
    workout.reload
  end

  it "re-applies the stored time shift on re-analysis, never falling back to the file's own dates (PLAN_DEMO.md §4)" do
    workout = imported_workout(time_shift: 86_400 * 195)
    shifted_start = workout.started_at
    shifted_segment_starts = workout.track_segments.pluck(:started_at)
    expect(workout.time_shift_seconds).to eq(86_400 * 195)

    workout.update_columns(analysis_version: 1)
    described_class.new(workout:).call!
    workout.reload

    expect(workout.started_at).to eq(shifted_start)
    expect(workout.track_segments.pluck(:started_at)).to eq(shifted_segment_starts)
  end

  it "re-places the workout's photos after a re-analysis, and only when it has some" do
    workout = imported_workout
    workout.update_columns(analysis_version: 1)
    expect { described_class.new(workout:).call! }.not_to have_enqueued_job(Workouts::PhotoPlacementJob)

    create(:workout_photo, workout:)
    workout.update_columns(analysis_version: 1)
    expect { described_class.new(workout: workout.reload).call! }.to have_enqueued_job(Workouts::PhotoPlacementJob).with(workout)
  end

  it "atomically replaces all derived metrics and recording segments" do
    workout = imported_workout
    old_segment_ids = workout.track_segment_ids
    workout.update_columns(
      analysis_version: 1,
      duration: 1,
      moving_time: 1,
      pause_time: 0,
      distance: 1,
      max_speed: 999,
      best_pace: 1
    )
    workout.laps.create!(number: 1, started_at: workout.started_at, elapsed_time: 1, moving_time: 1)

    described_class.new(workout:).call!
    workout.reload

    expect(workout).to have_attributes(
      analysis_version: Allure::Gpx::Analyzer::VERSION,
      duration: 180,
      moving_time: 180,
      pause_time: 0,
      points_count: 4,
      elevation_filter: "barometric"
    )
    expect(workout.distance).to be_within(0.001).of(483.11864482371004)
    expect(workout.max_speed).to be_within(0.0001).of(2.858159043012593)
    expect(workout.track_segment_ids).not_to eq(old_segment_ids)
    expect(workout.track_segments.first.points.length).to eq(4)
    expect(workout.laps).to be_empty
  end

  it "updates equipment totals and personal records from the rebuilt metrics" do
    workout = imported_workout
    workout.update_columns(
      analysis_version: 1,
      distance: 1,
      moving_time: 1,
      pause_time: workout.duration - 1,
      max_speed: 1,
      best_pace: 1000
    )
    equipment = create(:equipment, user:)
    Equipments::Totals.sync(workout, [ equipment.id ])

    described_class.new(workout:).call!
    workout.reload

    expect(equipment.reload).to have_attributes(
      total_distance: workout.distance,
      total_duration: workout.moving_time,
      total_moving: workout.moving_time
    )
    expect(Record.find_by!(user:, sport:, record_type: "MS")).to have_attributes(
      workout:,
      value: workout.max_speed,
      workout_started_at: workout.started_at
    )
  end

  it "rebuilds corrected FIT lap metrics and uses the device maximum" do
    started_at = Time.utc(2026, 5, 1, 8, 0, 0)
    bytes = build_fit(
      points: simple_fit_points(start: started_at),
      enhanced_max_speed: 14.25,
      laps: [
        {
          time: started_at + 90,
          elapsed: 90,
          moving: 80,
          distance: 405,
          max_speed: 12.5,
          avg_heart_rate: 140,
          lap_trigger: 1
        }
      ]
    )
    workout = Workouts::Importer.new(
      user:,
      sport:,
      uploaded_file: fit_io(bytes),
      filename: "ride.fit"
    ).call!
    workout.update_column(:analysis_version, 1)
    workout.laps.first.update_columns(elapsed_time: 1, moving_time: 1, max_speed: 1)

    described_class.new(workout:).call!
    workout.reload

    expect(workout.max_speed).to eq(14.25)
    expect(workout.laps.first).to have_attributes(
      elapsed_time: 90,
      moving_time: 80,
      distance: 405,
      max_speed: 12.5,
      average_heart_rate: 140,
      lap_trigger: "distance"
    )
  end

  it "does not mutate an active immutable publication" do
    workout = imported_workout
    publication = create(:workout_publication, workout:)
    snapshot = publication.attributes.slice("representation", "profile_snapshot", "route_metadata", "updated_at")
    workout.update_column(:analysis_version, 1)

    described_class.new(workout:).call!

    expect(publication.reload.attributes.slice(*snapshot.keys)).to eq(snapshot)
  end

  it "is a no-op at the current version without opening the original file" do
    workout = create(:workout, analysis_version: Allure::Gpx::Analyzer::VERSION)

    expect(described_class.new(workout:).call!).to eq(workout)
  end

  it "rolls back the workout and child replacement when persistence fails" do
    workout = imported_workout
    workout.update_column(:analysis_version, 1)
    original_metrics = workout.attributes.slice("analysis_version", "distance", "max_speed", "best_pace")
    original_segment_ids = workout.track_segment_ids
    allow_any_instance_of(TrackSegment).to receive(:save!).and_raise(ActiveRecord::RecordInvalid)

    expect { described_class.new(workout:).call! }.to raise_error(ActiveRecord::RecordInvalid)

    expect(workout.reload.attributes.slice(*original_metrics.keys)).to eq(original_metrics)
    expect(workout.track_segment_ids).to eq(original_segment_ids)
  end

  it "rejects a stale workout without its immutable source" do
    workout = create(:workout, analysis_version: 1)

    expect { described_class.new(workout:).call! }
      .to raise_error(described_class::MissingOriginalFileError)
  end

  describe "terrain elevation" do
    it "applies the cached terrain profile and forces the DEM threshold" do
      workout = with_terrain_profile(terrain_workout)

      described_class.new(workout:, force: true, elevation_source: "dem").call!
      workout.reload

      expect(workout.elevation_source).to eq("dem")
      expect(workout.elevation_source_requested).to be_nil
      expect(workout.recorded_elevation).to be(false)
      expect(workout.elevation_filter).to eq("dem")
      expect(workout.min_elevation).to eq(1000.0)
      expect(workout.max_elevation).to eq(1200.0)
      expect(workout.ascent).to be_within(0.01).of(200.0)
      expect(workout.track_segments.first.points.map { |point| point["ele"] }).to all(be_present)
    end

    it "degrades to the recorded profile when no terrain profile is cached" do
      workout = imported_workout
      workout.update_column(:analysis_version, 1)

      described_class.new(workout:, force: true, elevation_source: "dem").call!
      workout.reload

      expect(workout.elevation_source).to eq("device")
      expect(workout.recorded_elevation).to be(true)
      expect(workout.elevation_filter).to eq("barometric")
      expect(workout.min_elevation).to eq(2000.0)
    end

    it "reapplies the cached terrain profile while it is the effective source" do
      workout = with_terrain_profile(terrain_workout)
      workout.update!(elevation_source: "dem")

      described_class.new(workout:, force: true).call!

      expect(workout.reload.elevation_source).to eq("dem")
      expect(workout.elevation_filter).to eq("dem")
    end

    it "settles a pending source request" do
      workout = with_terrain_profile(terrain_workout)
      workout.update!(elevation_source_requested: "dem")

      described_class.new(workout:, force: true, elevation_source: "dem").call!

      expect(workout.reload.elevation_source_requested).to be_nil
    end
  end

  describe "device elevation totals" do
    def fit_workout(session_ascent:, session_descent:)
      bytes = build_fit(
        points: simple_fit_points,
        sport: 2,
        session_ascent:,
        session_descent:
      )
      Workouts::Importer.new(user:, sport:, uploaded_file: fit_io(bytes), filename: "ride.fit").call!
    end

    it "uses the device's own totals on a device run" do
      workout = fit_workout(session_ascent: 123, session_descent: 45)

      expect(workout.ascent).to eq(123.0)
      expect(workout.descent).to eq(45.0)

      workout.update_column(:analysis_version, 1)
      described_class.new(workout:).call!

      expect(workout.reload.ascent).to eq(123.0)
      expect(workout.descent).to eq(45.0)
    end

    it "ignores the device totals when the terrain profile is effective" do
      workout = fit_workout(session_ascent: 500, session_descent: 100)
      with_terrain_profile(workout, elevations: [ 1000.0, 1000.0, 1000.0 ])
      workout.update!(elevation_source: "dem")

      described_class.new(workout:, force: true).call!

      expect(workout.reload.elevation_source).to eq("dem")
      expect(workout.elevation_filter).to eq("dem")
      expect(workout.ascent).to eq(0.0)
    end

    it "ignores a rendered world's totals and repairs a stored zero" do
      bytes = build_fit(
        points: simple_fit_points,
        sport: 2,
        sub_sport: 58,
        session_ascent: 80,
        session_descent: 0,
        laps: [ { time: Time.utc(2026, 5, 1, 8, 3, 0), elapsed: 180, distance: 400, ascent: 0, descent: 0 } ]
      )
      workout = Workouts::Importer.new(
        user:, sport: catalog_sport("cycling_virtual"), uploaded_file: fit_io(bytes), filename: "zwift.fit"
      ).call!
      expect(workout.ascent).to eq(20.0)

      # A row stored before the fix: the platform's zeros, stale generation.
      workout.update_columns(ascent: 0.0, descent: 0.0, analysis_version: Allure::Gpx::Analyzer::VERSION - 1)
      described_class.new(workout:).call!

      expect(workout.reload.ascent).to eq(20.0)
      expect(workout.descent).to eq(0.0)
    end
  end

  describe "owner route image generation" do
    it "marks the image stale when a versioned re-analysis changes the geometry" do
      workout = imported_workout
      workout.update_columns(route_image_version: Workouts::RouteImage::VERSION, analysis_version: 1)
      # Simulate a stored geometry from an older analyzer generation.
      workout.track_segments.first.update_columns(
        geom: geographic_line_string([ [ 6.40, 45.06 ], [ 6.41, 45.07 ] ])
      )
      workout.association(:track_segments).reset

      described_class.new(workout:).call!

      expect(workout.reload.route_image_version).to eq(0)
    end

    it "keeps the image when a versioned re-analysis leaves the geometry alone" do
      workout = imported_workout
      workout.update_columns(route_image_version: Workouts::RouteImage::VERSION, analysis_version: 1)

      described_class.new(workout:).call!

      expect(workout.reload.route_image_version).to eq(Workouts::RouteImage::VERSION)
    end

    it "keeps the image when a forced run leaves the geometry alone" do
      workout = imported_workout
      workout.update_columns(route_image_version: Workouts::RouteImage::VERSION)

      described_class.new(workout:, force: true).call!

      expect(workout.reload.route_image_version).to eq(Workouts::RouteImage::VERSION)
    end
  end

  describe "toponymy" do
    include ActiveJob::TestHelper

    before { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }

    # The import already left a pending row; replace it with a settled one.
    def ready_toponymy(workout)
      workout.toponymy&.destroy!
      workout.association(:toponymy).reset
      create(:workout_toponymy, workout:)
    end

    it "re-geocodes when a versioned re-analysis changes the geometry" do
      workout = imported_workout
      toponymy = ready_toponymy(workout)
      workout.update_columns(analysis_version: 1)
      workout.track_segments.first.update_columns(
        geom: geographic_line_string([ [ 6.40, 45.06 ], [ 6.41, 45.07 ] ])
      )
      workout.association(:track_segments).reset

      expect { described_class.new(workout:).call! }
        .to have_enqueued_job(Workouts::EnrichToponymyJob).with(workout)
      expect(toponymy.reload).to be_pending
    end

    it "re-geocodes when the elevation source changes" do
      workout = with_terrain_profile(terrain_workout)
      ready_toponymy(workout)

      expect { described_class.new(workout:, force: true, elevation_source: "dem").call! }
        .to have_enqueued_job(Workouts::EnrichToponymyJob).with(workout)
    end

    it "keeps the places when neither the geometry nor the profile changed" do
      workout = imported_workout
      toponymy = ready_toponymy(workout)

      expect { described_class.new(workout:, force: true).call! }
        .not_to have_enqueued_job(Workouts::EnrichToponymyJob)
      expect(toponymy.reload).to be_ready
    end
  end
end
