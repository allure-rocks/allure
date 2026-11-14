# frozen_string_literal: true

module Auth
  # Authenticator-app codes (PLAN_AUTH.md §5.2): RFC 6238, SHA-1, six digits,
  # 30-second steps, one step of drift either way. A step at or below the last
  # accepted one is refused, so an observed code cannot be replayed.
  module Totp
    INTERVAL = 30
    DRIFT = 30
    CODE_FORMAT = /\A\d{6}\z/

    module_function

    def generate_secret = ROTP::Base32.random

    def provisioning_uri(user, secret)
      ROTP::TOTP.new(secret, issuer: Allure::Instance.name).provisioning_uri(user.handle)
    end

    def qr_svg(uri)
      RQRCode::QRCode.new(uri).as_svg(module_size: 4, standalone: true, use_path: true, viewbox: true,
                                      svg_attributes: { role: "img" })
    end

    def normalize(code) = code.to_s.gsub(/\s/, "")

    def code?(input) = CODE_FORMAT.match?(normalize(input))

    # The accepted step, or nil.
    def step_for(secret, code, after_step: nil, now: Time.current)
      normalized = normalize(code)
      return unless CODE_FORMAT.match?(normalized)

      timestamp = ROTP::TOTP.new(secret).verify(
        normalized, drift_behind: DRIFT, drift_ahead: DRIFT, after: after_step && (after_step * INTERVAL), at: now
      )
      timestamp && (timestamp / INTERVAL)
    end

    # Verifies an enrolled account's code and records its step atomically, so
    # two concurrent submissions of one code cannot both pass.
    def verify!(user, code, now: Time.current)
      return false unless user.totp_enrolled?

      step = step_for(user.otp_secret, code, after_step: user.otp_last_used_step, now:)
      return false unless step

      User.where(id: user.id)
        .where("otp_last_used_step IS NULL OR otp_last_used_step < ?", step)
        .update_all(otp_last_used_step: step) == 1
    end
  end
end
