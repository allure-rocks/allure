# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261028090000_reconcile_existing_loop_detections").to_s

RSpec.describe ReconcileExistingLoopDetections do
  include ActiveJob::TestHelper

  def migrate
    migration = described_class.new
    migration.suppress_messages { migration.migrate(:up) }
  end

  it "invalidates even current positioned recordings and queues one low-priority sweep without deleting loops" do
    current = create(:workout, loop_reuse_version: 3)
    stale = create(:workout, loop_reuse_version: 2)
    never_matched = create(:workout, loop_reuse_version: 0)
    indoor = create(:workout, :unpositioned, loop_reuse_version: 3)
    manual = create(:workout, :manual, loop_reuse_version: 3)
    credit = create(:workout, :credit, credited_from: current, loop_reuse_version: 3)
    future = create(:workout, loop_reuse_version: 4)
    loop_segment = create(:segment, :loop, user: current.user, source_workout: current)

    expect { migrate }.to have_enqueued_job(Segments::BackfillLoopReuseJob)
      .with(no_args).at_priority(BacklogPriority::PRIORITY).exactly(:once)

    expect([ current, stale, never_matched ].map { |workout| workout.reload.loop_reuse_version }).to eq([ 0, 0, 0 ])
    expect([ indoor, manual, credit, future ].map { |workout| workout.reload.loop_reuse_version }).to eq([ 3, 3, 3, 4 ])
    expect(loop_segment.reload).to be_persisted
  end

  it "does not enqueue anything on a fresh installation or with only positionless recordings" do
    expect { migrate }.not_to have_enqueued_job(Segments::BackfillLoopReuseJob)
    create(:workout, :unpositioned, loop_reuse_version: 3)

    expect { migrate }.not_to have_enqueued_job(Segments::BackfillLoopReuseJob)
  end

  it "fails visibly when enqueueing is aborted and can be retried without losing the pending work" do
    workout = create(:workout, loop_reuse_version: 3)
    configured = instance_double(ActiveJob::ConfiguredJob, perform_later: false)
    allow(Segments::BackfillLoopReuseJob).to receive(:set).and_return(configured)

    expect { migrate }.to raise_error(ActiveRecord::MigrationError, /retry the migration/)
    expect(workout.reload.loop_reuse_version).to eq(0)

    allow(Segments::BackfillLoopReuseJob).to receive(:set).and_call_original
    expect { migrate }.to have_enqueued_job(Segments::BackfillLoopReuseJob)
  end

  it "keeps current loop identities and converges duplicate effort histories after the sweep" do
    allow(Segments::BackfillSegmentJob).to receive(:perform_later)
    user = create(:user)
    sport = create(:sport)
    first = import_fixture(user, sport, "three_laps.gpx")
    Segments::MatchWorkoutJob.perform_now(first)
    keeper = Segment.find_by!(source_workout: first, kind: "loop")
    second = import_fixture(user, sport, "three_laps_recorded.gpx")
    Segments::MatchWorkoutJob.perform_now(second)
    duplicate = create(:segment, :loop, user:, source_workout: second,
      geom: keeper.geom, start_point: keeper.start_point, end_point: keeper.end_point,
      bounds: keeper.bounds, distance: keeper.distance, name: "Legacy duplicate")
    second.segment_efforts.update_all(segment_id: duplicate.id)
    original_name = keeper.name
    publication = create(:workout_publication, workout: first)
    snapshot = publication.attributes

    perform_enqueued_jobs(only: [ Segments::BackfillLoopReuseJob, Segments::MatchWorkoutJob ]) { migrate }

    expect(Segment.where(kind: "loop").pluck(:id)).to eq([ keeper.id ])
    expect(keeper.reload).to have_attributes(name: original_name, efforts_count: 6)
    expect(first.reload.loop_reuse_version).to eq(Segments::LoopReuse::VERSION)
    expect(second.reload.loop_reuse_version).to eq(Segments::LoopReuse::VERSION)
    expect(second.detected_laps.where(source: "loop").count).to eq(3)
    expect(Segments::BackfillLoopReuseJob.pending_scope).to be_empty
    expect(publication.reload.attributes).to eq(snapshot)
  end

  def import_fixture(user, sport, filename)
    file = ActionDispatch::Http::UploadedFile.new(
      tempfile: File.open(Rails.root.join("spec/fixtures/gpx/#{filename}")),
      filename:, type: "application/gpx+xml"
    )
    Workouts::Importer.new(user:, sport:, uploaded_file: file).call.workout
  end
end
