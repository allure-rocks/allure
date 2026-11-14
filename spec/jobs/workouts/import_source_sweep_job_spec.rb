# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workouts::ImportSourceSweepJob do
  let(:user) { create(:user, locale: "en") }
  let(:now) { Time.current }

  def batch_with_upload(status:, updated_at: now)
    batch = create(:workout_import_batch, user:, sport: catalog_sport("cycling"), status:)
    batch.source_files.attach(io: StringIO.new("<gpx/>"), filename: "ride.gpx", content_type: "application/gpx+xml")
    batch.update_columns(updated_at:)
    batch
  end

  it "frees the uploads of finished batches and keeps those of running ones" do
    finished = %w[completed failed cancelled].map { |status| batch_with_upload(status:) }
    running = batch_with_upload(status: "processing")

    described_class.perform_now(now:)

    expect(finished.map { it.reload.source_files.attached? }).to all(be(false))
    expect(running.reload.source_files).to be_attached
  end

  it "fails an uploaded batch stalled for a week, then frees its upload" do
    stalled = batch_with_upload(status: "processing", updated_at: now - 8.days)
    entry = stalled.entries.create!(source_key: "1:0", position: 0, source_name: "ride.gpx", status: "queued")
    recent = batch_with_upload(status: "queued", updated_at: now - 6.days)

    described_class.perform_now(now:)

    expect(stalled.reload).to have_attributes(status: "failed", error_message: "stopped after 7 days without progress")
    expect(entry.reload).to have_attributes(status: "failed")
    expect(stalled.source_files).not_to be_attached
    expect(recent.reload).to have_attributes(status: "queued")
    expect(recent.source_files).to be_attached
  end
end
