# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workouts::UserBackfillJob do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }
  let(:other) { create(:user) }

  before { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }

  def with_original_file(workout)
    workout.original_file.attach(
      io: StringIO.new("bytes"), filename: "ride.fit", content_type: "application/octet-stream"
    )
    workout
  end

  it "counts every kind for the account" do
    with_original_file(create(:workout, user:, import_detection_version: 0))

    counts = described_class.counts(user)

    expect(counts.keys).to contain_exactly("rebuild", "route_images", "segment_images", "places", "elevation", "weather",
                                         "loops", "heart_rate", "route_suggestions")
    expect(counts.fetch("rebuild")).to eq(1)
  end

  it "enqueues one newest-first sweep for the route suggestions kind" do
    create(:workout, user:, route_suggestion_version: 0)

    expect { described_class.perform_now(user.id, "route_suggestions") }
      .to have_enqueued_job(Segments::RouteSuggestionSweepJob).with(user.id)
  end

  it "rejects an unknown kind" do
    expect { described_class.pending_scope(user, "nonsense") }.to raise_error(ArgumentError)
  end

  it "enqueues the account's stale rebuilds only" do
    mine = with_original_file(create(:workout, user:, import_detection_version: 0))
    with_original_file(create(:workout, user: other, import_detection_version: 0))

    expect { described_class.perform_now(user.id, "rebuild") }
      .to have_enqueued_job(Workouts::RebuildJob).with(mine)
    expect(Workouts::RebuildJob).to have_been_enqueued.exactly(:once)
  end

  it "enqueues route image renders for the account's missing images only" do
    mine = create(:workout, user:, route_image_version: 0)
    create(:workout, user: other, route_image_version: 0)

    expect { described_class.perform_now(user.id, "route_images") }
      .to have_enqueued_job(Workouts::RenderRouteImageJob).with(mine)
    expect(Workouts::RenderRouteImageJob).to have_been_enqueued.exactly(:once)
  end

  it "enqueues segment image renders for the account's missing images only" do
    mine = create(:segment, user:, route_image_version: 0)
    create(:segment, user: other, route_image_version: 0)
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    expect { described_class.perform_now(user.id, "segment_images") }
      .to have_enqueued_job(Segments::RenderRouteImageJob).with(mine)
    expect(Segments::RenderRouteImageJob).to have_been_enqueued.exactly(:once)
  end

  it "enqueues loop reconciliation for the account's stale loops only" do
    mine = create(:workout, user:, loop_reuse_version: 0)
    create(:segment, :loop, user:, source_workout: mine)
    other_workout = create(:workout, user: other, loop_reuse_version: 0)
    create(:segment, :loop, user: other, source_workout: other_workout)
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    expect { described_class.perform_now(user.id, "loops") }
      .to have_enqueued_job(Segments::MatchWorkoutJob).with(mine)
    expect(Segments::MatchWorkoutJob).to have_been_enqueued.exactly(:once)
  end

  it "dispatches place assembly and geocoding repairs to their jobs" do
    assembly = create(:workout, user:)
    create(:workout_toponymy, workout: assembly, status: "ready")
    geocoding = create(:workout, user:)
    create(:workout_toponymy, workout: geocoding, status: "failed")
    outdated = create(:workout, user:)
    create(:workout_toponymy, workout: outdated, status: "ready",
                              algorithm_version: Workouts::ToponymyEnricher::ALGORITHM_VERSION - 1)

    expect { described_class.perform_now(user.id, "places") }
      .to have_enqueued_job(Workouts::RebuildPlacesJob).with(assembly)
      .and have_enqueued_job(Workouts::EnrichToponymyJob).with(geocoding)
      .and have_enqueued_job(Workouts::EnrichToponymyJob).with(outdated)
    expect(Workouts::RebuildPlacesJob).to have_been_enqueued.exactly(:once)
  end

  it "never geocodes a virtual workout" do
    virtual = create(:workout, user:, sport: create(:sport, virtual: true))

    expect(described_class.pending_scope(user, "places")).not_to include(virtual)
  end

  it "finds no elevation work without a provider" do
    create(:workout, user:, min_elevation: nil, max_elevation: nil, recorded_elevation: false)

    expect(described_class.pending_scope(user, "elevation")).to be_empty
  end

  it "enqueues the terrain apply for an opted-in account" do
    allow(Allure::Elevation::Config).to receive(:configured?).and_return(true)
    opted_in = create(:user, elevation_enrichment_enabled: true)
    workout = create(:workout, user: opted_in, min_elevation: nil, max_elevation: nil, recorded_elevation: false)

    expect { described_class.perform_now(opted_in.id, "elevation") }
      .to have_enqueued_job(Workouts::ApplyElevationSourceJob).with(workout, "dem")
  end

  it "resumes from the cursor when a batch fills" do
    stub_const("Workouts::UserBackfillJob::BATCH_SIZE", 1)
    first = with_original_file(create(:workout, user:, import_detection_version: 0))
    with_original_file(create(:workout, user:, import_detection_version: 0))

    expect { described_class.perform_now(user.id, "rebuild", after_id: 0) }
      .to have_enqueued_job(described_class).with(user.id, "rebuild", after_id: first.id)
  end
end
