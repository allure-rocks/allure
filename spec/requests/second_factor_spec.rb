# frozen_string_literal: true

require "rails_helper"

# docs/dev/AUTH.md: the second step of a password sign-in, the grace
# period and the enrolment-only session, enrolment of each factor, recovery
# codes, re-authentication with a factor, and the operator's step-up.
RSpec.describe "Second factor" do
  include ActiveSupport::Testing::TimeHelpers
  include ActiveJob::TestHelper

  let(:user) { create(:user) }
  let(:enrolled) { create(:user, :with_totp) }
  let(:passkey_client) { WebAuthn::FakeClient.new(Allure::Federation.config.base_url) }

  def post_password(account)
    post session_path, params: { email_address: account.email_address, password: "allure-test-password" }
  end

  def code_for(account, at: Time.current) = ROTP::TOTP.new(account.reload.otp_secret).at(at)

  def add_passkey(account)
    options = Auth::Passkeys.registration_options(account)
    raw = passkey_client.create(challenge: options.challenge, rp_id: Allure::Federation.config.host)
    Auth::Passkeys.register(account, raw.to_json, challenge: options.challenge, nickname: "Phone")
  end

  def passkey_assertion(options_path)
    post options_path, as: :json
    challenge = response.parsed_body.fetch("challenge")
    passkey_client.get(challenge:, rp_id: Allure::Federation.config.host).to_json
  end

  describe "sign-in with an enrolled account" do
    it "creates no session until the second step passes" do
      post_password(enrolled)

      expect(response).to redirect_to(new_session_challenge_path)
      expect(enrolled.sessions).to be_empty

      get me_path
      expect(response).to redirect_to(new_session_path)
    end

    it "signs in with an authenticator code and records the factor" do
      post_password(enrolled)
      get new_session_challenge_path
      expect(response.body).to include("Vérification en deux étapes", 'autocomplete="one-time-code"')

      post session_challenge_path, params: { code: code_for(enrolled) }

      expect(response).to redirect_to(me_url)
      expect(enrolled.sessions.sole).to have_attributes(second_factor_method: "totp", enrolment_only: false)
    end

    it "returns to the requested page after the second step" do
      get settings_units_path
      post_password(enrolled)
      post session_challenge_path, params: { code: code_for(enrolled) }

      expect(response).to redirect_to(settings_units_url)
    end

    it "refuses a wrong code and ends the attempt after five" do
      post_password(enrolled)

      4.times do
        post session_challenge_path, params: { code: "000000" }
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("Ce code ne correspond pas.")
      end
      post session_challenge_path, params: { code: "000000" }

      expect(response).to redirect_to(new_session_path)
      expect(flash[:alert]).to eq("Trop d'essais. Saisissez à nouveau votre mot de passe.")
      post session_challenge_path, params: { code: code_for(enrolled) }
      expect(response).to redirect_to(new_session_path)
      expect(enrolled.sessions).to be_empty
    end

    it "expires the pending step after five minutes" do
      post_password(enrolled)

      travel 6.minutes do
        post session_challenge_path, params: { code: code_for(enrolled) }
      end

      expect(response).to redirect_to(new_session_path)
      expect(enrolled.sessions).to be_empty
    end

    it "is invalidated by a password change" do
      post_password(enrolled)
      enrolled.update!(password: "rotated-password-1", password_confirmation: "rotated-password-1")

      post session_challenge_path, params: { code: code_for(enrolled) }

      expect(response).to redirect_to(new_session_path)
    end

    it "refuses to replay a code" do
      code = code_for(enrolled)
      post_password(enrolled)
      post session_challenge_path, params: { code: }
      delete session_path

      post_password(enrolled)
      post session_challenge_path, params: { code: }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "accepts a recovery code once and mails the account" do
      code = RecoveryCode.generate_for!(enrolled).first
      post_password(enrolled)

      expect do
        post session_challenge_path, params: { code: code.upcase }
      end.to have_enqueued_mail(SecurityMailer, :notice)

      expect(response).to redirect_to(me_url)
      expect(enrolled.sessions.sole.second_factor_method).to eq("recovery_code")

      delete session_path
      post_password(enrolled)
      post session_challenge_path, params: { code: }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "draws the code as six slots and offers recovery codes on request" do
      post_password(enrolled)
      get new_session_challenge_path

      otp = response.parsed_body.at_css('.otp[data-controller="otp"] input[name="code"]')
      expect(otp["maxlength"]).to eq("6")
      expect(response.body).to include(new_session_challenge_path(recovery: 1))

      get new_session_challenge_path(recovery: 1)
      expect(response.parsed_body.at_css('input[name="recovery_code"]')).to be_present
      expect(response.parsed_body.at_css('input[name="code"]')).to be_nil

      code = RecoveryCode.generate_for!(enrolled).first
      post session_challenge_path, params: { recovery_code: code }
      expect(response).to redirect_to(me_url)
    end

    it "offers a passkey-only account its passkey, without a code field" do
      account = create(:user)
      add_passkey(account)
      post_password(account)
      get new_session_challenge_path

      expect(response.parsed_body.at_css('input[name="code"]')).to be_nil
      expect(response.body).to include("Utiliser une clé d&#39;accès")
    end

    it "signs in with a passkey" do
      add_passkey(enrolled)
      post_password(enrolled)
      get new_session_challenge_path
      expect(response.body).to include("Utiliser une clé d&#39;accès")

      post session_challenge_path, params: { assertion: passkey_assertion(options_session_challenge_path) }

      expect(response).to redirect_to(me_url)
      expect(enrolled.sessions.sole.second_factor_method).to eq("webauthn")
    end

    it "answers the options request only during a pending sign-in" do
      post options_session_challenge_path, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it "never lets the challenge page bypass the password" do
      get new_session_challenge_path

      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "grace period" do
    it "signs a new account straight in and reminds it on every page" do
      post_password(user)

      expect(response).to redirect_to(me_url)
      get settings_units_path
      expect(response.body).to include("Activez la double authentification avant le", "Il reste 14 jours.")
    end

    it "hides the reminder for the rest of the day" do
      post_password(user)
      post settings_dismiss_second_factor_reminder_path, headers: { "Referer" => settings_units_url }

      expect(response).to redirect_to(settings_units_url)
      get settings_units_path
      expect(response.body).not_to include("Activez la double authentification avant le")
    end

    it "restricts an open session once the deadline passes" do
      post_password(user)

      travel 15.days do
        get settings_units_path
        expect(response).to redirect_to(settings_security_path)
        expect(user.sessions.sole).to be_enrolment_only
      end
    end
  end

  describe "enrolment-only session" do
    before do
      user.update_column(:second_factor_required_since, 20.days.ago)
      post_password(user)
    end

    it "lands on the security page with the obligation stated" do
      expect(response).to redirect_to(settings_security_path)
      follow_redirect!

      expect(response.body).to include("La double authentification est obligatoire pour ce compte.")
      expect(response.body).not_to include("notifications/badge")
      expect(user.sessions.sole).to be_enrolment_only
    end

    it "reaches nothing else" do
      get me_path
      expect(response).to redirect_to(settings_security_path)

      get workouts_path, headers: { "Turbo-Frame" => "workouts" }
      expect(response).to have_http_status(:no_content)
    end

    it "can still sign out" do
      delete session_path

      expect(response).to redirect_to(new_session_path)
      expect(user.sessions).to be_empty
    end

    it "becomes a full session once an authenticator app is set up, and shows the recovery codes once" do
      get new_settings_totp_path
      expect(response.body).to include("Configurer une application d&#39;authentification", "<svg")
      secret = session[:pending_otp_secret]["secret"]

      expect do
        post settings_totp_path, params: { code: ROTP::TOTP.new(secret).now }
      end.to have_enqueued_mail(SecurityMailer, :notice)

      expect(response).to redirect_to(settings_recovery_codes_path)
      expect(user.reload).to be_totp_enrolled
      expect(user.sessions.sole).to have_attributes(enrolment_only: false, second_factor_method: "totp")

      get settings_recovery_codes_path
      codes = response.parsed_body.css(".recovery-codes li").map(&:text)
      expect(codes.size).to eq(10)
      expect(response.headers["Cache-Control"]).to include("no-store")

      get settings_recovery_codes_path
      expect(response).to redirect_to(settings_security_path)

      get me_path
      expect(response).to have_http_status(:ok)
    end

    it "refuses a wrong enrolment code" do
      get new_settings_totp_path
      post settings_totp_path, params: { code: "000000" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Ce code ne correspond pas.")
      expect(user.reload).not_to be_totp_enrolled
    end

    it "becomes a full session once a passkey is added" do
      post settings_passkeys_path, params: {
        nickname: "YubiKey",
        credential: (post(options_settings_passkeys_path, as: :json) &&
          passkey_client.create(challenge: response.parsed_body["challenge"], rp_id: Allure::Federation.config.host).to_json)
      }

      expect(response).to redirect_to(settings_recovery_codes_path)
      expect(user.webauthn_credentials.sole.nickname).to eq("YubiKey")
      expect(user.sessions.sole).not_to be_enrolment_only
    end

    it "signs out an enrolment-only session whose account was enrolled elsewhere" do
      user.update!(otp_secret: ROTP::Base32.random, otp_enrolled_at: Time.current)

      get settings_security_path

      expect(response).to redirect_to(new_session_path)
      expect(flash[:notice]).to eq("La double authentification est maintenant active sur ce compte. Reconnectez-vous pour l'utiliser.")
      expect(user.sessions).to be_empty
    end

    it "closes other password-only sessions once enrolled" do
      other = user.sessions.create!(enrolment_only: true)
      get new_settings_totp_path
      post settings_totp_path, params: { code: ROTP::TOTP.new(session[:pending_otp_secret]["secret"]).now }

      expect(Session.exists?(other.id)).to be(false)
    end
  end

  describe "managing factors" do
    before { sign_in_as(enrolled) }

    it "refuses to remove the last factor of a password account" do
      delete settings_totp_path

      expect(response).to redirect_to(settings_security_path)
      expect(flash[:alert]).to include("Ajoutez une autre méthode")
      expect(enrolled.reload).to be_totp_enrolled
    end

    it "removes the authenticator app when a passkey remains" do
      add_passkey(enrolled)

      expect { delete settings_totp_path }.to have_enqueued_mail(SecurityMailer, :notice)
      expect(enrolled.reload).not_to be_totp_enrolled
    end

    it "removes a passkey when the authenticator app remains" do
      credential = add_passkey(enrolled)

      delete settings_passkey_path(credential)

      expect(response).to redirect_to(settings_security_path)
      expect(flash[:alert]).to be_nil
      expect(enrolled.webauthn_credentials.reload).to be_empty
    end

    it "regenerates the recovery codes" do
      old = RecoveryCode.generate_for!(enrolled).first

      post settings_recovery_codes_path

      expect(response).to redirect_to(settings_recovery_codes_path)
      expect(RecoveryCode.consume(enrolled, old)).to be(false)
      expect(enrolled.recovery_codes.unused.count).to eq(10)
    end

    it "lists the factors on the security page" do
      add_passkey(enrolled)
      RecoveryCode.generate_for!(enrolled)

      get settings_security_path

      expect(response.body).to include("Double authentification", "Configurée le", "Phone", "10 codes restants sur 10.")
    end
  end

  describe "re-authentication with a factor" do
    before do
      sign_in_as(enrolled)
      travel 11.minutes
    end

    after { travel_back }

    it "asks for the password and a second factor" do
      get new_reauthentication_path

      expect(response.body).to include("confirmez avec votre double authentification", 'name="code"')
    end

    it "refuses the password alone" do
      post reauthentication_path, params: { password: "allure-test-password" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Le mot de passe ou la vérification ne correspond pas.")
    end

    it "accepts the password with a code and records the factor" do
      post reauthentication_path, params: { password: "allure-test-password", code: code_for(enrolled) }

      expect(response).to redirect_to(settings_security_path)
      expect(enrolled.sessions.sole.reload).to be_recent_second_factor
    end
  end

  describe "password managers" do
    let(:companion) { { "User-Agent" => "Allure iOS/1.0 Hotwire Native iOS; bridge-components: [topbar]" } }

    def credential_page
      Nokogiri::HTML(response.body)
    end

    it "loads the sign-in and challenge pages in full and submits them natively in a browser" do
      get new_session_path
      expect(credential_page.at_css("meta[name='turbo-visit-control']")["content"]).to eq("reload")
      expect(credential_page.at_css("form[action='#{session_path}']")["data-turbo"]).to eq("false")

      post_password(enrolled)
      get new_session_challenge_path
      expect(credential_page.at_css("meta[name='turbo-visit-control']")["content"]).to eq("reload")
      expect(credential_page.at_css("form[action='#{session_challenge_path}']")["data-turbo"]).to eq("false")
    end

    it "keeps Turbo in the iOS companion" do
      get new_session_path, headers: companion

      expect(credential_page.at_css("meta[name='turbo-visit-control']")).to be_nil
      expect(credential_page.at_css("form[action='#{session_path}']")["data-turbo"]).to be_nil
    end
  end

  describe "operator" do
    around do |example|
      previous = ENV["INSTANCE_OPERATOR_USERNAME"]
      ENV["INSTANCE_OPERATOR_USERNAME"] = "operator"
      example.run
    ensure
      previous.nil? ? ENV.delete("INSTANCE_OPERATOR_USERNAME") : ENV["INSTANCE_OPERATOR_USERNAME"] = previous
    end

    it "has no grace period" do
      operator = create(:user, username: "operator")

      post_password(operator)

      expect(response).to redirect_to(settings_security_path)
      expect(operator.sessions.sole).to be_enrolment_only
    end

    it "confirms a second factor again after fifteen minutes in the console" do
      operator = create(:user, :with_totp, username: "operator")
      sign_in_as(operator)
      get admin_root_path
      expect(response).to have_http_status(:ok)

      travel 16.minutes do
        get admin_root_path
        expect(response).to redirect_to(new_reauthentication_path)

        get new_reauthentication_path
        form = Nokogiri::HTML(response.body).at_css("form[action='#{reauthentication_path}']")
        expect(form["data-turbo"]).to eq("false")
        expect(form.at_css("input[type=hidden][autocomplete=username]")["value"]).to eq(operator.email_address)

        post reauthentication_path, params: { password: "allure-test-password", code: code_for(operator) }
        expect(response).to redirect_to(admin_root_path)
        get admin_root_path
        expect(response).to have_http_status(:ok)
      end
    end

    it "resets another account's factors, audited and mailed" do
      operator = create(:user, :with_totp, username: "operator")
      add_passkey(enrolled)
      enrolled.sessions.create!
      sign_in_as(operator)

      expect do
        post admin_account_reset_second_factor_path(enrolled)
      end.to have_enqueued_mail(SecurityMailer, :notice)

      expect(enrolled.reload).to have_attributes(otp_secret: nil, sessions: [])
      expect(enrolled.webauthn_credentials.reload).to be_empty
      expect(AdminEvent.last).to have_attributes(action: "second_factor_reset", subject: enrolled)
      expect(Auth::SecondFactorPolicy.new(enrolled)).to be_required
    end

    it "cannot reset its own factors from the console" do
      operator = create(:user, :with_totp, username: "operator")
      sign_in_as(operator)

      post admin_account_reset_second_factor_path(operator)

      expect(operator.reload).to be_totp_enrolled
    end
  end

  describe "security email" do
    it "is localized to the account" do
      mail = SecurityMailer.notice(create(:user, locale: "en"), "passkey_added").message

      expect(mail.subject).to eq("New passkey on your Allure account")
      expect(mail.text_part.body.decoded).to include("A new passkey was just added", "/settings/security")
    end
  end

  describe "apple-app-site-association" do
    around do |example|
      previous = ENV["IOS_APP_IDS"]
      example.run
    ensure
      previous.nil? ? ENV.delete("IOS_APP_IDS") : ENV["IOS_APP_IDS"] = previous
    end

    it "is absent until the app identifiers are configured" do
      ENV.delete("IOS_APP_IDS")
      get apple_app_site_association_path

      expect(response).to have_http_status(:not_found)
    end

    it "lists the configured apps for passkeys" do
      ENV["IOS_APP_IDS"] = "ABCDE12345.app.allure.ios, not-an-id"
      get apple_app_site_association_path

      expect(response.parsed_body).to eq("webcredentials" => { "apps" => [ "ABCDE12345.app.allure.ios" ] })
    end
  end
end
