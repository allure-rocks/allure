# frozen_string_literal: true

# The account lifecycle mails (PLAN_ACCOUNT.md): a ready export, a scheduled
# or cancelled deletion, and the deletion done. Localized to the account,
# since the mails are queued. The last one is sent after the row is gone, so
# it takes the address and locale captured before the purge, never the row.
class AccountMailer < ApplicationMailer
  def export_ready(export)
    @user = export.user
    @export = export
    I18n.with_locale(@user.locale) do
      mail subject: I18n.t("account_mailer.export_ready.subject"), to: @user.email_address
    end
  end

  def deletion_scheduled(user)
    @user = user
    I18n.with_locale(user.locale) do
      @date = I18n.l(user.deletion_scheduled_at.in_time_zone(user.time_zone), format: :long)
      mail subject: I18n.t("account_mailer.deletion_scheduled.subject"), to: user.email_address
    end
  end

  def deletion_cancelled(user)
    @user = user
    I18n.with_locale(user.locale) do
      mail subject: I18n.t("account_mailer.deletion_cancelled.subject"), to: user.email_address
    end
  end

  def deleted(email_address:, locale:, username:)
    @username = username
    I18n.with_locale(User::LOCALES.include?(locale) ? locale : I18n.default_locale) do
      mail subject: I18n.t("account_mailer.deleted.subject"), to: email_address
    end
  end
end
