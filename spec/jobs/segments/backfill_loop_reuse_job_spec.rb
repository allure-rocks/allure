# frozen_string_literal: true

require "rails_helper"

RSpec.describe Segments::BackfillLoopReuseJob do
  include ActiveJob::TestHelper

  def import_fixture(user, sport, filename)
    file = ActionDispatch::Http::UploadedFile.new(
      tempfile: File.open(Rails.root.join("spec/fixtures/gpx/#{filename}")),
      filename:,
      type: "application/gpx+xml"
    )
    Workouts::Importer.new(user:, sport:, uploaded_file: file).call.workout
  end

  it "includes positioned recordings without an existing loop, but not current or positionless workouts" do
    pending_workout = create(:workout, loop_reuse_version: 0)
    create(:segment, :loop, user: pending_workout.user, source_workout: pending_workout)
    reconciled = create(:workout, loop_reuse_version: Segments::LoopReuse::VERSION)
    create(:segment, :loop, user: reconciled.user, source_workout: reconciled)
    missing_loop = create(:workout, loop_reuse_version: 2)
    create(:workout, start_point: nil, bounds: nil)

    expect(described_class.pending_scope).to contain_exactly(pending_workout, missing_loop)
  end

  it "enqueues a match for pending workouts only" do
    pending_workout = create(:workout, loop_reuse_version: 0)
    create(:segment, :loop, user: pending_workout.user, source_workout: pending_workout)
    reconciled = create(:workout, loop_reuse_version: Segments::LoopReuse::VERSION)
    create(:segment, :loop, user: reconciled.user, source_workout: reconciled)
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    expect { described_class.perform_now }
      .to have_enqueued_job(Segments::MatchWorkoutJob).with(pending_workout)
    expect(Segments::MatchWorkoutJob).to have_been_enqueued.exactly(:once)
  end

  it "converges a legacy duplicate loop onto the oldest one" do
    user = create(:user)
    sport = create(:sport)
    first = import_fixture(user, sport, "three_laps.gpx")
    Segments::MatchWorkoutJob.perform_now(first)
    keeper = Segment.find_by!(source_workout: first, kind: "loop")

    second = import_fixture(user, sport, "three_laps_recorded.gpx")
    Segments::MatchWorkoutJob.perform_now(second)
    duplicate = create(
      :segment, :loop,
      user:, source_workout: second,
      geom: keeper.geom, start_point: keeper.start_point, end_point: keeper.end_point,
      bounds: keeper.bounds, distance: keeper.distance
    )
    second.segment_efforts.update_all(segment_id: duplicate.id)
    duplicate.update_columns(efforts_count: second.segment_efforts.count)
    second.update_columns(loop_reuse_version: 0)

    perform_enqueued_jobs(only: Segments::MatchWorkoutJob) do
      described_class.perform_now
    end

    expect(Segment.where(kind: "loop").pluck(:id)).to eq([ keeper.id ])
    expect(keeper.reload.efforts_count).to eq(6)
  end

  it "recovers a single known-loop traversal missed by the previous generation" do
    user = create(:user)
    sport = create(:sport)
    source = import_fixture(user, sport, "three_laps.gpx")
    Segments::MatchWorkoutJob.perform_now(source)
    loop_segment = Segment.find_by!(source_workout: source, kind: "loop")
    missed = import_fixture(user, sport, "three_laps_recorded.gpx")
    track = missed.track_segments.sole
    track.update!(points: track.points.first(5), points_count: 5)
    missed.update_columns(loop_reuse_version: 2)

    perform_enqueued_jobs(only: Segments::MatchWorkoutJob) do
      described_class.perform_now
    end

    expect(missed.segment_efforts.where(segment: loop_segment).count).to eq(1)
    expect(missed.detected_laps.where(source: "loop").count).to eq(1)
    expect(missed.reload.loop_reuse_version).to eq(Segments::LoopReuse::VERSION)
    expect(described_class.pending_scope).to be_empty
  end

  it "resumes from the cursor when a batch fills" do
    stub_const("Segments::BackfillLoopReuseJob::BATCH_SIZE", 1)
    first = create(:workout, loop_reuse_version: 0)
    create(:segment, :loop, user: first.user, source_workout: first)
    second = create(:workout, loop_reuse_version: 0)
    create(:segment, :loop, user: second.user, source_workout: second)
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    expect { described_class.perform_now(after_id: 0) }
      .to have_enqueued_job(described_class).with(after_id: first.id)
  end
end
