# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Account lifecycle jobs (docs/dev/ACCOUNT.md)" do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }

  describe Users::ExportJob do
    it "builds the archive, keeps it seven days, and tells the account" do
      export = user.account_exports.create!

      freeze_time do
        described_class.perform_now(export.id)

        expect(export.reload).to have_attributes(status: "ready", expires_at: 7.days.from_now)
      end
      expect(export.archive).to be_attached
      expect(export.byte_size).to eq(export.archive.byte_size)
      expect(export.counts).to include("workouts" => 0)
      expect(Notification.where(user:, kind: "account_export_ready", subject: export)).to exist
      expect(enqueued_jobs.map { it["arguments"]&.first(2) }).to include(%w[AccountMailer export_ready])
    end

    it "marks the export failed and tells nobody when the build fails" do
      export = user.account_exports.create!
      allow(Users::ExportArchive).to receive(:new).and_raise(RuntimeError, "boom")

      described_class.perform_now(export.id)

      expect(export.reload).to have_attributes(status: "failed", error_code: "build_failed")
      expect(Notification.where(user:, kind: "account_export_ready")).to be_empty
    end

    it "builds a pending export only once" do
      export = user.account_exports.create!(status: "running")

      described_class.perform_now(export.id)

      expect(export.reload.status).to eq("running")
    end
  end

  describe Users::AccountExportSweepJob do
    it "expires past-due exports and closes stale builds" do
      ready = user.account_exports.create!(status: "ready", completed_at: 8.days.ago, expires_at: 1.day.ago)
      ready.archive.attach(io: StringIO.new("zip"), filename: "a.zip")
      fresh = create(:user).account_exports.create!(status: "ready", completed_at: 1.hour.ago, expires_at: 6.days.from_now)
      stale = create(:user).account_exports.create!(status: "running")
      stale.update_columns(updated_at: 2.days.ago)

      perform_enqueued_jobs { described_class.perform_now }

      expect(ready.reload.status).to eq("expired")
      expect(ready.archive).not_to be_attached
      expect(fresh.reload.status).to eq("ready")
      expect(stale.reload).to have_attributes(status: "failed", error_code: "interrupted")
    end
  end

  describe Users::AccountDeletionSweepJob do
    it "starts the purge of every account whose window has ended" do
      due = create(:user, deletion_requested_at: 8.days.ago, deletion_scheduled_at: 1.hour.ago, deletion_requested_by: "self")
      create(:user, deletion_requested_at: 1.day.ago, deletion_scheduled_at: 6.days.from_now, deletion_requested_by: "self")

      described_class.perform_now

      expect(Users::AccountPurgeJob).to have_been_enqueued.with(due.id).exactly(:once)
    end
  end

  describe Users::AccountPurgeJob do
    it "purges in batches and mails the captured address once the row is gone" do
      user.update!(deletion_requested_at: 8.days.ago, deletion_scheduled_at: 1.hour.ago, deletion_requested_by: "self")
      create_list(:workout, 3, user:)
      stub_const("#{described_class}::BATCH", 2)
      address = user.email_address

      described_class.perform_now(user.id)

      expect(user.reload.workouts.count).to eq(1)
      expect(described_class).to have_been_enqueued.with(user.id)

      described_class.perform_now(user.id)

      expect(User.exists?(user.id)).to be(false)
      mail = enqueued_jobs.find { it["job_class"] == "ActionMailer::MailDeliveryJob" && it["arguments"][0..1] == %w[AccountMailer deleted] }
      expect(mail.to_s).to include(address)
    end

    it "leaves an account whose window is still open" do
      user.update!(deletion_requested_at: 1.day.ago, deletion_scheduled_at: 6.days.from_now, deletion_requested_by: "self")

      described_class.perform_now(user.id)

      expect(User.exists?(user.id)).to be(true)
    end

    it "stops without a mail when the deletion was cancelled while the purge started" do
      user.update!(deletion_requested_at: 8.days.ago, deletion_scheduled_at: 1.hour.ago, deletion_requested_by: "self")
      service = instance_double(Users::DeleteAccount)
      allow(Users::DeleteAccount).to receive(:new).with(user:, require_scheduled: true).and_return(service)
      allow(service).to receive(:call!).and_raise(Users::DeleteAccount::Cancelled)

      expect { described_class.perform_now(user.id) }.not_to raise_error
      expect(described_class).not_to have_been_enqueued
      expect(enqueued_jobs.find { it["arguments"]&.first(2) == %w[AccountMailer deleted] }).to be_nil
    end
  end
end
