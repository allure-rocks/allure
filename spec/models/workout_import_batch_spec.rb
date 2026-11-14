# frozen_string_literal: true

require "rails_helper"

RSpec.describe WorkoutImportBatch do
  let(:user) { create(:user) }
  let(:sport) { create(:sport) }
  let(:batch) { create(:workout_import_batch, user:, sport:) }

  describe "#progress_percentage" do
    it "is zero until the total is known" do
      expect(batch.progress_percentage).to eq(0)
    end

    it "floors the processed share and caps it at 100" do
      batch.update!(total_entries: 3, processed_entries: 1)
      expect(batch.progress_percentage).to eq(33)

      batch.update!(processed_entries: 4)
      expect(batch.progress_percentage).to eq(100)
    end
  end

  describe "#refresh_progress!" do
    it "freezes the discovered total and counts only terminal rows as processed" do
      create(:workout_import_entry, batch:, status: "queued", position: 0, source_key: "1:0")
      create(:workout_import_entry, batch:, status: "processing", position: 1, source_key: "1:1")
      create(:workout_import_entry, batch:, status: "imported", position: 2, source_key: "1:2")
      create(:workout_import_entry, batch:, status: "duplicate", position: 3, source_key: "1:3")
      create(:workout_import_entry, batch:, status: "failed", position: 4, source_key: "1:4")
      create(:workout_import_entry, batch:, status: "cancelled", position: 5, source_key: "1:5")

      batch.refresh_progress!

      expect(batch.reload).to have_attributes(
        total_entries: 6,
        processed_entries: 4,
        imported_entries: 1,
        failed_entries: 1,
        duplicate_entries: 1,
        cancelled_entries: 1
      )
      expect(batch.progress_percentage).to eq(66)
    end
  end

  describe "options card" do
    it "accepts the title up to the workout limit" do
      batch.title = "a" * 255
      expect(batch).to be_valid

      batch.title = "a" * 256
      expect(batch).not_to be_valid
      expect(batch.errors[:title]).to be_present
    end

    it "defaults to a non-commute batch with no gear" do
      expect(batch).not_to be_commute
      expect(batch.equipment_ids).to be_empty
    end
  end
end
