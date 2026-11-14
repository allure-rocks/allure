class PasswordsMailer < ApplicationMailer
  # Localized to the account, not the request: reset mails are queued with
  # deliver_later, so no request locale exists when the message is built.
  def reset(user)
    @user = user
    I18n.with_locale(user.locale) do
      mail subject: I18n.t("passwords_mailer.reset.subject"), to: user.email_address
    end
  end
end
