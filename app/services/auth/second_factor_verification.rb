# frozen_string_literal: true

module Auth
  # Checks one second-factor answer (docs/dev/AUTH.md): a passkey assertion
  # when one was sent, otherwise a six-digit authenticator code, otherwise a
  # recovery code. Returns the method that passed, or nil.
  module SecondFactorVerification
    module_function

    def call(user, code: nil, assertion: nil, challenge: nil, now: Time.current)
      if assertion.present?
        Passkeys.authenticate(user, assertion, challenge:, now:) ? :webauthn : nil
      elsif Totp.code?(code)
        Totp.verify!(user, code, now:) ? :totp : nil
      elsif code.present? && RecoveryCode.consume(user, code, now:)
        SecurityMailer.notice(user, "recovery_code_used", remaining: user.recovery_codes.unused.count).deliver_later
        :recovery_code
      end
    end
  end
end
