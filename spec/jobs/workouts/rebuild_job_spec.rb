# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workouts::RebuildJob do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }
  let!(:rowing) { catalog_sport("rowing") }
  let!(:rowing_virtual) { catalog_sport("rowing_virtual") }
  let(:start) { Time.utc(2026, 5, 1, 8, 0, 0) }

  before { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }

  # EXR file at Henley: the fingerprint names the device, the FIT sport
  # resolves to virtual rowing, and the start point is in a known world.
  def exr_bytes
    points = [
      { time: start, lat: 51.545, lon: -0.885, altitude: 20.0 },
      { time: start + 60, lat: 51.5452, lon: -0.8848, altitude: 20.0 },
      { time: start + 120, lat: 51.5454, lon: -0.8846, altitude: 20.0 }
    ]
    build_fit(points:, sport: 15, sub_sport: 14, product_name: nil,
              manufacturer: 255, product: 22, serial_number: 1234)
  end

  # Simulates a workout imported before the platform catalogue existed: the
  # file was mapped to the plain sport, the device was left unnamed, no venue
  # was stored, and the detection generation is the initial one.
  def legacy_workout(sport: rowing)
    Workouts::Importer.new(user:, sport: nil, uploaded_file: fit_upload(exr_bytes)).call!.tap do |workout|
      workout.update_columns(sport_id: sport.id, source: nil, places: [], import_detection_version: 0)
      workout.place_names.delete_all
      # The import enqueued its own route image and matching jobs; only what
      # the rebuild enqueues is under test.
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    end
  end

  def entry_for(workout, sport_source: "detected")
    create(:workout_import_entry, workout:, status: "imported", sport_source:)
  end

  it "fills the device, re-detects a detected sport, and names the virtual venue" do
    workout = legacy_workout
    entry_for(workout)
    create(:workout_toponymy, workout:)

    described_class.perform_now(workout)

    workout.reload
    expect(workout.source).to eq("EXR")
    expect(workout.sport).to eq(rowing_virtual)
    expect(workout.toponymy).to be_nil
    expect(workout.places).to eq([ { "name" => "Henley", "kind" => "virtual_venue" } ])
    expect(workout.place_names.pluck(:name)).to eq([ "Henley" ])
    expect(workout.import_detection_version).to eq(Workouts::ImportDetection::VERSION)
    expect(Segments::MatchWorkoutJob).to have_been_enqueued.with(workout)
  end

  it "never overwrites a stored device" do
    workout = legacy_workout
    workout.update_columns(source: "My Rower")
    entry_for(workout)

    described_class.perform_now(workout)

    expect(workout.reload.source).to eq("My Rower")
  end

  it "replaces a manufacturer name the superseded table derived" do
    workout = legacy_workout
    workout.update_columns(source: "Polar")

    described_class.perform_now(workout)

    expect(workout.reload.source).to eq("EXR")
  end

  it "leaves a sport changed by hand alone but still fills the device" do
    workout = legacy_workout
    entry_for(workout, sport_source: "manual")

    described_class.perform_now(workout)

    workout.reload
    expect(workout.sport).to eq(rowing)
    expect(workout.source).to eq("EXR")
    expect(workout.places).to be_empty
    expect(workout.import_detection_version).to eq(Workouts::ImportDetection::VERSION)
  end

  it "leaves the sport alone without an import entry" do
    workout = legacy_workout

    described_class.perform_now(workout)

    expect(workout.reload.sport).to eq(rowing)
  end

  it "re-analyses a stale analyzer generation, parsing the file once" do
    workout = legacy_workout(sport: rowing_virtual)
    workout.update_columns(analysis_version: 1, route_image_version: Workouts::RouteImage::VERSION)
    allow(Workouts::OriginalTrack).to receive(:new).and_call_original

    described_class.perform_now(workout)

    workout.reload
    expect(workout.analysis_version).to eq(Allure::Gpx::Analyzer::VERSION)
    expect(Segments::MatchWorkoutJob).to have_been_enqueued.with(workout)
    expect(Workouts::OriginalTrack).to have_received(:new).once
    # The recomputed geometry matches the stored one: no needless re-render.
    expect(workout.route_image_version).to eq(Workouts::RouteImage::VERSION)
    expect(Workouts::RenderRouteImageJob).not_to have_been_enqueued
  end

  it "marks the route image stale when a re-analysis changes the geometry" do
    workout = legacy_workout(sport: rowing_virtual)
    workout.update_columns(analysis_version: 1, route_image_version: Workouts::RouteImage::VERSION)
    workout.track_segments.first.update_columns(
      geom: geographic_line_string([ [ -0.885, 51.545 ], [ -0.8851, 51.5451 ] ])
    )
    workout.association(:track_segments).reset

    described_class.perform_now(workout)

    expect(workout.reload.route_image_version).to eq(0)
    expect(Workouts::RenderRouteImageJob).to have_been_enqueued.with(workout)
  end

  it "does not enqueue a route image that is already current" do
    workout = legacy_workout
    entry_for(workout)
    workout.update_columns(route_image_version: Workouts::RouteImage::VERSION)

    described_class.perform_now(workout)

    expect(Workouts::RenderRouteImageJob).not_to have_been_enqueued
  end

  it "reports an unreadable original file and leaves the facts pending" do
    workout = legacy_workout
    workout.original_file.attach(io: StringIO.new("not a fit file"), filename: "broken.fit",
                                 content_type: "application/octet-stream")
    entry_for(workout)
    allow(Rails.error).to receive(:report)

    described_class.perform_now(workout)

    expect(Rails.error).to have_received(:report).with(
      an_instance_of(Allure::Fit::MalformedFitError),
      handled: true,
      context: hash_including(workout_id: workout.id)
    )
    expect(workout.reload.import_detection_version).to eq(0)
    expect(workout.source).to be_nil
  end
end
