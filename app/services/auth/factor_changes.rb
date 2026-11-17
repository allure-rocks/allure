# frozen_string_literal: true

module Auth
  # What follows a change to an account's second factors (docs/dev/AUTH.md):
  # recovery codes at the first enrolment, the enrolling session lifted out of
  # enrolment-only, other enrolment-only sessions closed, and a security email.
  module FactorChanges
    module_function

    # Returns the fresh recovery codes when this was the first factor.
    def enrolled!(user, method:, event:, session: nil, now: Time.current)
      first = !user.recovery_codes.exists?
      codes = nil
      User.transaction do
        codes = RecoveryCode.generate_for!(user) if first
        # A session that only proved the password must not inherit the new
        # factor; the enrolling session is the one that carries it.
        others = user.sessions.where(enrolment_only: true)
        others = others.where.not(id: session.id) if session
        others.destroy_all
        session&.complete_enrolment!(now, method:)
      end
      SecurityMailer.notice(user, event).deliver_later
      codes
    end

    def removed!(user, event:)
      SecurityMailer.notice(user, event).deliver_later
    end

    def recovery_codes_regenerated!(user)
      codes = RecoveryCode.generate_for!(user)
      SecurityMailer.notice(user, "recovery_codes_regenerated").deliver_later
      codes
    end

    # Operator reset (docs/dev/AUTH.md): every factor goes, every session
    # closes, and the next password sign-in leads straight to enrolment.
    def reset!(user, now: Time.current)
      User.transaction do
        user.webauthn_credentials.delete_all
        user.recovery_codes.delete_all
        user.sessions.destroy_all
        user.update!(otp_secret: nil, otp_enrolled_at: nil, otp_last_used_step: nil,
                     second_factor_required_since: now - Allure::Auth::Config.second_factor_grace)
      end
      SecurityMailer.notice(user, "second_factor_reset").deliver_later
    end

    # A password account may not remove its last factor (docs/dev/AUTH.md).
    def removable?(user)
      user.password_digest.blank? || user.second_factor_count > 1
    end
  end
end
