# frozen_string_literal: true

require "rails_helper"

RSpec.describe ImportMailer do
  %w[fr en].each do |locale|
    context "in #{locale}" do
      let(:user) { create(:user, locale:) }

      it "announces a finished Strava archive with its counts, photos and the batch page" do
        batch = create(:workout_import_batch, user:, sport: nil, source: "strava_archive", status: "completed",
                                              imported_entries: 1220, duplicate_entries: 14)
        create(:workout_import_entry, batch:, status: "imported", metadata: { "photos" => 106, "photos_missing" => 76 })

        mail = described_class.strava_archive_finished(batch)

        expect(mail.to).to eq([ user.email_address ])
        expect(mail.subject).to eq(I18n.t("import_mailer.strava_archive_finished.completed.subject", locale:))
        body = mail.text_part.body.to_s
        expect(body).to include("1220", "14", "106", "76", "/workout_imports/#{batch.to_param}")
        expect(mail.html_part.body.to_s).to include("/workout_imports/#{batch.to_param}")
      end

      it "names why a Strava archive failed" do
        batch = create(:workout_import_batch, user:, sport: nil, source: "strava_archive", status: "failed",
                                              error_message: "activities.csv est introuvable")

        mail = described_class.strava_archive_finished(batch)

        expect(mail.subject).to eq(I18n.t("import_mailer.strava_archive_finished.failed.subject", locale:))
        expect(mail.text_part.body.to_s).to include("activities.csv est introuvable")
      end
    end
  end
end
