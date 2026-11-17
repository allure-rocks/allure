# frozen_string_literal: true

require "rails_helper"

# The browser session's unfinished authentication steps belong to whoever was
# using the browser (docs/dev/AUTH.md): sign-in and every end of a session clear
# them, and per-account values are bound to their account.
RSpec.describe "Authentication flow state" do
  let(:first) { create(:user, :with_totp) }
  let(:second) { create(:user, :with_totp) }

  def pending_secret = session[:pending_otp_secret]&.fetch("secret")

  it "never hands an abandoned authenticator secret to the next account" do
    sign_in_as(first)
    get new_settings_totp_path
    planted = pending_secret
    expect(planted).to be_present

    delete session_path
    expect(session[:pending_otp_secret]).to be_nil

    sign_in_as(second)
    get new_settings_totp_path
    expect(pending_secret).to be_present
    expect(pending_secret).not_to eq(planted)
    expect(response.body).not_to include(planted.scan(/.{1,4}/).join(" "))
  end

  it "never shows one account's fresh recovery codes to another" do
    sign_in_as(first)
    post settings_recovery_codes_path
    expect(session[:fresh_recovery_codes]).to include("user_id" => first.id)

    delete session_path
    sign_in_as(second)
    get settings_recovery_codes_path

    expect(response).to redirect_to(settings_security_path)
  end

  context "when a value survives into another account's session" do
    # The binding holds even if an exit forgot to clear the flow.
    before { allow_any_instance_of(ApplicationController).to receive(:clear_authentication_flow) }

    it "generates a fresh authenticator secret for the other account" do
      sign_in_as(first)
      get new_settings_totp_path
      planted = pending_secret
      delete session_path

      sign_in_as(second)
      get new_settings_totp_path

      expect(session[:pending_otp_secret]).to include("user_id" => second.id)
      expect(pending_secret).not_to eq(planted)
    end

    it "refuses an authenticator code for the other account's secret" do
      sign_in_as(first)
      get new_settings_totp_path
      planted = pending_secret
      delete session_path

      sign_in_as(second)
      post settings_totp_path, params: { code: ROTP::TOTP.new(planted).now }

      expect(second.reload.otp_secret).not_to eq(planted)
    end

    it "does not show the other account's recovery codes" do
      sign_in_as(first)
      post settings_recovery_codes_path
      delete session_path

      sign_in_as(second)
      get settings_recovery_codes_path

      expect(response).to redirect_to(settings_security_path)
    end
  end

  describe "every end of a session clears the flow" do
    before do
      sign_in_as(first)
      get new_settings_totp_path
    end

    it "on closing every session" do
      get new_reauthentication_path # keep the gate satisfied: signing in counts
      delete settings_destroy_all_security_sessions_path

      expect(session[:pending_otp_secret]).to be_nil
    end

    it "when the session expires" do
      first.sessions.sole.update_columns(last_seen_at: 31.days.ago)
      get me_path

      expect(session[:pending_otp_secret]).to be_nil
    end

    it "when the account is suspended" do
      first.update!(suspended_at: Time.current)
      get me_path

      expect(session[:pending_otp_secret]).to be_nil
    end
  end

  it "keeps the page a signed-out visitor asked for through sign-in" do
    get settings_security_path
    sign_in_as(first)

    expect(response).to redirect_to(settings_security_url)
  end

  describe "cancelling" do
    it "ends a pending second step" do
      post session_path, params: { email_address: first.email_address, password: "allure-test-password" }
      expect(session[:pending_sign_in]).to be_present

      post cancel_session_challenge_path

      expect(response).to redirect_to(new_session_path)
      expect(session[:pending_sign_in]).to be_nil
      get new_session_challenge_path
      expect(response).to redirect_to(new_session_path)
    end

    it "discards a provider identity waiting for account creation" do
      with_providers do
        mock_provider(:google)
        sign_in_with(:google)
        expect(session[:pending_identity]).to be_present

        delete onboarding_path

        expect(response).to redirect_to(new_session_path)
        expect(session[:pending_identity]).to be_nil
      end
    end
  end
end
