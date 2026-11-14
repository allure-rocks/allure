# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workouts::ImportAdmission do
  let(:user) { create(:user) }
  let(:now) { Time.zone.parse("2026-10-24 12:00:00 UTC") }
  let(:archive) { Allure::ImportSources::STRAVA_ARCHIVE.key }

  def admission(source: "file", bytes: 1.megabyte) = described_class.new(user:, source:, bytes:, now:)

  def batch(source: "file", status: "queued", bytes: 0, created_at: now - 1.hour)
    create(:workout_import_batch, user:, source:, status:, source_bytes: bytes, created_at:,
                                  sport: source == "file" ? catalog_sport("cycling") : nil)
  end

  it "admits an upload within every limit" do
    expect(admission.refusal).to be_nil
  end

  it "refuses a file import while three are waiting or running" do
    2.times { batch }
    batch(status: "processing")
    batch(status: "completed")

    expect(admission.refusal).to have_attributes(reason: "too_many_active_imports")
  end

  it "refuses a second Strava archive, but not a file import beside it" do
    batch(source: archive, status: "processing")

    expect(admission(source: archive).refusal).to have_attributes(reason: "archive_in_progress")
    expect(admission.refusal).to be_nil
  end

  it "admits the day's budget exactly, and refuses a byte more" do
    batch(status: "completed", bytes: described_class::DAILY_UPLOAD_BYTES - 1.megabyte, created_at: now - 3.hours)

    expect(admission(bytes: 1.megabyte).refusal).to be_nil

    refusal = admission(bytes: 1.megabyte + 1).refusal
    expect(refusal).to have_attributes(reason: "upload_budget_exceeded", retry_after: 21.hours.to_i)
  end

  it "forgets uploads older than a day and other accounts' uploads" do
    batch(status: "completed", bytes: described_class::DAILY_UPLOAD_BYTES, created_at: now - 25.hours)
    create(:workout_import_batch, status: "completed", source_bytes: described_class::DAILY_UPLOAD_BYTES,
                                  created_at: now - 1.hour)

    expect(admission(bytes: 1.gigabyte).refusal).to be_nil
  end
end
