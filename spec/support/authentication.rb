# frozen_string_literal: true

module AuthenticationHelpers
  # Signs in through the real forms. An account with an authenticator app
  # answers the second step with its current code (docs/dev/AUTH.md).
  def sign_in_as(user, password: "allure-test-password")
    post session_path, params: { email_address: user.email_address, password: }
    return unless response.redirect? && response.location.end_with?(new_session_challenge_path)

    # A second sign-in in the same 30 seconds would replay the code; tests are
    # not testing replay here.
    user.update_column(:otp_last_used_step, nil)
    post session_challenge_path, params: { code: current_totp_code(user) }
  end

  def current_totp_code(user, at: Time.current)
    ROTP::TOTP.new(user.reload.otp_secret).at(at)
  end
end

RSpec.configure do |config|
  config.include AuthenticationHelpers, type: :request
end
