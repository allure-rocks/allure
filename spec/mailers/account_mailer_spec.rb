# frozen_string_literal: true

require "rails_helper"

RSpec.describe AccountMailer do
  %w[fr en].each do |locale|
    context "in #{locale}" do
      let(:user) { create(:user, locale:) }

      it "announces a ready export with its expiry" do
        export = user.account_exports.create!(status: "ready", completed_at: Time.current, expires_at: 7.days.from_now)

        mail = described_class.export_ready(export)

        expect(mail.to).to eq([ user.email_address ])
        expect(mail.subject).to eq(I18n.t("account_mailer.export_ready.subject", locale:))
        expect(mail.text_part.body.to_s).to include("/settings/account")
      end

      it "announces a scheduled deletion, cancellable unless the operator asked" do
        Users::DeletionSchedule.new(user:).schedule!(by: "self")
        expect(described_class.deletion_scheduled(user).text_part.body.to_s).to include("/settings/account/deletion")

        user.update!(deletion_requested_by: "operator")
        operator_mail = described_class.deletion_scheduled(user).text_part.body.to_s
        expect(operator_mail).not_to include("/settings/account/deletion")
      end

      it "confirms a cancellation and the deletion itself" do
        expect(described_class.deletion_cancelled(user).subject).to eq(I18n.t("account_mailer.deletion_cancelled.subject", locale:))

        mail = described_class.deleted(email_address: "gone@allure.test", locale:, username: "gone")
        expect(mail.to).to eq([ "gone@allure.test" ])
        expect(mail.text_part.body.to_s).to include("@gone")
      end
    end
  end
end
