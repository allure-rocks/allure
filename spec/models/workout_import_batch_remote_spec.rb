# frozen_string_literal: true

require "rails_helper"

RSpec.describe WorkoutImportBatch, "remote sources" do
  let(:user) { create(:user) }
  let(:connection) { create(:import_connection, :linked, user:) }

  it "requires a sport for an uploaded batch only" do
    expect(build(:workout_import_batch, user:, sport: nil)).not_to be_valid
    expect(build(:workout_import_batch, user:, sport: nil, source: "garmin_connect", import_connection: connection)).to be_valid

    batch = create(:workout_import_batch, user:)
    expect { batch.update_column(:sport_id, nil) }.to raise_error(ActiveRecord::StatementInvalid)
  end

  it "keeps the retrieval range ordered" do
    batch = build(:workout_import_batch, user:, sport: nil, source: "garmin_connect", import_connection: connection,
                                         range_from: Date.new(2026, 6, 2), range_to: Date.new(2026, 6, 1))

    expect(batch).not_to be_valid
    expect { batch.save!(validate: false) }.to raise_error(ActiveRecord::StatementInvalid)
  end

  it "counts skipped entries as processed, apart from failures and duplicates" do
    batch = create(:workout_import_batch, user:, sport: nil, source: "garmin_connect", import_connection: connection)
    create(:workout_import_entry, batch:, status: "skipped", skip_reason: "no_geometry")
    create(:workout_import_entry, batch:, status: "queued")

    batch.refresh_progress!

    expect(batch).to have_attributes(total_entries: 2, processed_entries: 1, skipped_entries: 1, failed_entries: 0)
  end

  it "ties a skipped entry to its reason" do
    batch = create(:workout_import_batch, user:)
    entry = build(:workout_import_entry, batch:, status: "skipped")

    expect(entry).not_to be_valid
    expect { entry.save!(validate: false) }.to raise_error(ActiveRecord::StatementInvalid)
    expect(build(:workout_import_entry, batch:, status: "failed", skip_reason: "no_file")).not_to be_valid
  end
end
