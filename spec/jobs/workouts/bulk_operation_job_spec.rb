# frozen_string_literal: true

require "rails_helper"

# The durable executor of confirmed bulk operations (PLAN_BULK_ACTIONS.md §5):
# per-item outcomes, resumability, cancellation, and a report that survives a
# deletion.
RSpec.describe Workouts::BulkOperationJob do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }
  let(:cycling) { catalog_sport("cycling") }
  let(:running) { catalog_sport("running") }

  before { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }

  def imported_workout(sport: cycling)
    upload = ActionDispatch::Http::UploadedFile.new(
      tempfile: File.open(Rails.root.join("spec/fixtures/gpx/galibier.gpx")),
      filename: "galibier.gpx",
      type: "application/gpx+xml"
    )
    Workouts::Importer.new(user:, sport:, uploaded_file: upload).call!
  end

  def operation_for(operation, workouts)
    parameters = operation == "sport_change" ? { "sport_id" => running.id } : {}
    record = create(:workout_bulk_operation, user:, operation:, parameters:, status: "queued")
    workouts.each_with_index do |workout, index|
      create(:workout_bulk_operation_item, operation: record, workout:, position: index)
    end
    record
  end

  it "changes the sport of every item and completes" do
    workout = imported_workout
    record = operation_for("sport_change", [ workout ])
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    described_class.perform_now(record.id, record.user_id)

    expect(record.reload.status).to eq("completed")
    expect(workout.reload.sport).to eq(running)
    item = record.items.first.reload
    expect(item.status).to eq("modified")
    expect(item.failure_code).to be_nil
  end

  it "skips workouts without an original file" do
    workout = create(:workout, user:, sport: cycling)
    record = operation_for("sport_change", [ workout ])

    described_class.perform_now(record.id, record.user_id)

    item = record.items.first.reload
    expect(item.status).to eq("skipped")
    expect(item.failure_code).to eq("missing_original_file")
    expect(workout.reload.sport).to eq(cycling)
    expect(record.reload.status).to eq("completed")
  end

  it "deletes every item and keeps the report after the workout is gone" do
    workout = create(:workout, user:, sport: cycling)
    record = operation_for("delete", [ workout ])

    described_class.perform_now(record.id, record.user_id)

    expect(Workout.exists?(workout.id)).to be(false)
    item = record.items.first.reload
    expect(item.status).to eq("modified")
    expect(item.workout_id).to be_nil
    expect(record.reload.status).to eq("completed")
  end

  it "skips an item whose workout vanished before the run" do
    workout = create(:workout, user:, sport: cycling)
    record = operation_for("delete", [ workout ])
    workout.destroy!

    described_class.perform_now(record.id, record.user_id)

    item = record.items.first.reload
    expect(item.status).to eq("skipped")
    expect(item.failure_code).to eq("workout_missing")
  end

  it "resumes in batches and re-enqueues itself while work remains" do
    first = create(:workout, user:, sport: cycling)
    second = create(:workout, user:, sport: cycling)
    record = operation_for("delete", [ first, second ])
    stub_const("Workouts::BulkOperationJob::BATCH_SIZE", 1)

    described_class.perform_now(record.id, record.user_id)

    expect(record.reload.status).to eq("processing")
    expect(record.items.in_order.map(&:status)).to eq(%w[modified queued])
    expect(described_class).to have_been_enqueued.with(record.id, record.user_id)

    described_class.perform_now(record.id, record.user_id)

    expect(record.reload.status).to eq("completed")
    expect(record.items.in_order.map(&:status)).to eq(%w[modified modified])
  end

  # The queue adapter evaluates the concurrency key at enqueue time; the test
  # adapter never does. This reads the real key against the arguments the job
  # actually re-enqueues (an Integer id used to raise NoMethodError on
  # `operation.user_id`, stopping the operation after the first batch).
  it "re-enqueues arguments its concurrency key can read" do
    first = create(:workout, user:, sport: cycling)
    second = create(:workout, user:, sport: cycling)
    record = operation_for("delete", [ first, second ])
    stub_const("Workouts::BulkOperationJob::BATCH_SIZE", 1)

    described_class.perform_now(record.id, record.user_id)

    args = ActiveJob::Base.queue_adapter.enqueued_jobs
      .select { |job| job[:job] == described_class }
      .last
      .fetch(:args)
    expect(args).to eq([ record.id, record.user_id ])
    expect(described_class.new(*args).concurrency_key)
      .to eq("Workouts::BulkOperationJob/workout-bulk-#{record.user_id}")
  end

  it "cancels the remaining items when cancellation was requested" do
    first = create(:workout, user:, sport: cycling)
    second = create(:workout, user:, sport: cycling)
    record = operation_for("delete", [ first, second ])
    record.update!(cancellation_requested_at: Time.current)

    described_class.perform_now(record.id, record.user_id)

    expect(record.reload.status).to eq("cancelled")
    expect(record.items.in_order.map(&:status)).to eq(%w[cancelled cancelled])
    expect(Workout.exists?(first.id)).to be(true)
    expect(Workout.exists?(second.id)).to be(true)
  end

  it "is idempotent for an already-changed sport" do
    workout = imported_workout
    Workouts::SportChange.new(workout:, sport: running).call!
    record = operation_for("sport_change", [ workout ])
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    described_class.perform_now(record.id, record.user_id)

    expect(record.items.first.reload.status).to eq("modified")
    expect(workout.reload.sport).to eq(running)
    expect(record.reload.status).to eq("completed")
  end

  it "ignores a terminal operation" do
    workout = create(:workout, user:, sport: cycling)
    record = operation_for("delete", [ workout ])
    record.complete!

    described_class.perform_now(record.id, record.user_id)

    expect(Workout.exists?(workout.id)).to be(true)
    expect(record.items.first.reload.status).to eq("queued")
  end
end
