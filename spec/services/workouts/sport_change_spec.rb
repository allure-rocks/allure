# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workouts::SportChange do
  let(:user) { create(:user) }
  let(:cycling) { catalog_sport("cycling") }
  let(:running) { catalog_sport("running") }

  before do
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  end

  def imported_workout(sport: cycling)
    upload = ActionDispatch::Http::UploadedFile.new(
      tempfile: File.open(Rails.root.join("spec/fixtures/gpx/galibier.gpx")),
      filename: "galibier.gpx",
      type: "application/gpx+xml"
    )
    Workouts::Importer.new(user:, sport:, uploaded_file: upload).call!
  end

  # An EXR file whose start point sits in the Henley world: the importer
  # detects virtual rowing and names the venue.
  def imported_exr
    catalog_sport("rowing_virtual")
    points = [
      { time: Time.utc(2026, 5, 1, 8, 0, 0), lat: 51.545, lon: -0.885, altitude: 20.0 },
      { time: Time.utc(2026, 5, 1, 8, 1, 0), lat: 51.5452, lon: -0.8848, altitude: 20.0 },
      { time: Time.utc(2026, 5, 1, 8, 2, 0), lat: 51.5454, lon: -0.8846, altitude: 20.0 }
    ]
    bytes = build_fit(points:, sport: 15, sub_sport: 14, product_name: nil,
                      manufacturer: 255, product: 22, serial_number: 1234)
    Workouts::Importer.new(user:, sport: nil, uploaded_file: fit_upload(bytes)).call!
  end

  it "re-analyses the workout with the new sport and rebuilds its best efforts" do
    workout = imported_workout
    expect(workout.grade_adjusted_pace).to be_nil
    expect(workout.best_efforts).to be_empty
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    described_class.new(workout:, sport: running).call!

    workout.reload
    expect(workout.sport).to eq(running)
    expect(workout.grade_adjusted_pace).to be_present
    expect(workout.best_efforts.map(&:sport_id).uniq).to eq([ running.id ])
    expect(workout.best_efforts).not_to be_empty
    expect(Segments::MatchWorkoutJob).to have_been_enqueued.with(workout)
  end

  it "recomputes moving time with the new stopped-speed threshold" do
    workout = imported_workout
    stopping = create(:sport, stopped_speed_threshold: 50.0, records_elevation: false)

    described_class.new(workout:, sport: stopping).call!

    workout.reload
    expect(workout.sport).to eq(stopping)
    expect(workout.moving_time).to eq(0)
    expect(workout.pause_time).to eq(workout.duration)
  end

  it "reassigns the personal records of both sports" do
    workout = imported_workout
    expect(Record.find_by(user:, sport: cycling, record_type: "FD").workout).to eq(workout)

    described_class.new(workout:, sport: running).call!

    expect(Record.find_by(user:, sport: cycling, record_type: "FD")).to be_nil
    expect(Record.find_by(user:, sport: running, record_type: "FD").workout).to eq(workout)
  end

  it "is a no-op when the sport is unchanged" do
    workout = imported_workout
    segment_ids = workout.track_segment_ids
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    expect(described_class.new(workout:, sport: cycling).call!).to eq(workout)

    expect(workout.reload.track_segment_ids).to eq(segment_ids)
    expect(Segments::MatchWorkoutJob).not_to have_been_enqueued
  end

  it "records a manual change on the import entry" do
    workout = imported_workout
    entry = create(:workout_import_entry, workout:, sport_source: "detected")

    described_class.new(workout:, sport: running).call!
    expect(entry.reload.sport_source).to eq("manual")

    described_class.new(workout:, sport: cycling, provenance: "detected").call!
    expect(entry.reload.sport_source).to eq("detected")
  end

  it "discards the toponymy and names the venue when moving to a virtual sport" do
    rowing_virtual = catalog_sport("rowing_virtual")
    workout = imported_exr
    described_class.new(workout:, sport: cycling).call!
    expect(workout.reload.toponymy).to be_pending
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    described_class.new(workout:, sport: rowing_virtual).call!

    workout.reload
    expect(workout.sport).to eq(rowing_virtual)
    expect(workout.toponymy).to be_nil
    expect(workout.places).to eq([ { "name" => "Henley", "kind" => "virtual_venue" } ])
    expect(Workouts::EnrichToponymyJob).not_to have_been_enqueued
  end

  it "clears the venue and re-enqueues geocoding when leaving a virtual sport" do
    workout = imported_exr
    expect(workout.places).to eq([ { "name" => "Henley", "kind" => "virtual_venue" } ])
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    described_class.new(workout:, sport: cycling).call!

    workout.reload
    expect(workout.sport).to eq(cycling)
    expect(workout.places).to eq([])
    expect(workout.place_names).to be_empty
    expect(Workouts::EnrichToponymyJob).to have_been_enqueued.with(workout)
  end

  it "refuses a workout without its original file" do
    workout = create(:workout, user:, sport: cycling)

    expect { described_class.new(workout:, sport: running).call! }
      .to raise_error(described_class::MissingOriginalFile)
    expect(workout.reload.sport).to eq(cycling)
    expect(Segments::MatchWorkoutJob).not_to have_been_enqueued
  end

  it "rolls the change back when the re-analysis fails" do
    workout = imported_workout
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    allow_any_instance_of(Workouts::Reanalyzer).to receive(:call!).and_raise(ArgumentError, "boom")

    expect { described_class.new(workout:, sport: running).call! }
      .to raise_error(described_class::ReanalysisFailed, /boom/)
    expect(workout.reload.sport).to eq(cycling)
    expect(Segments::MatchWorkoutJob).not_to have_been_enqueued
  end
end
