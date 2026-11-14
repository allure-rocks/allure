# frozen_string_literal: true

require "rails_helper"

# PLAN_AUTH.md slice 3: signing in, signing up, linking and re-authenticating
# through an identity provider, and password-less accounts.
RSpec.describe "Identity providers" do
  include ActiveSupport::Testing::TimeHelpers
  include ActiveJob::TestHelper

  around { |example| with_providers { example.run } }

  let(:google_issuer) { Allure::Auth::Providers::GOOGLE_ISSUER }

  def link_identity(user, provider: "google", subject: "subject-1", issuer: google_issuer)
    user.identities.create!(provider:, issuer:, subject:, email: user.email_address, email_verified: true,
                            linked_at: Time.current)
  end

  def passwordless_user(**attributes)
    create(:user, password: nil, password_confirmation: nil, provider_signup: true, **attributes).tap do |user|
      link_identity(user)
    end
  end

  describe "sign-in page" do
    it "offers each enabled provider through a POST form outside Turbo" do
      get new_session_path

      forms = response.parsed_body.css('form[action^="/auth/"]')
      expect(forms.map { |form| form["action"] }).to eq(%w[/auth/google?intent=sign_in /auth/apple?intent=sign_in
                                                         /auth/oidc?intent=sign_in])
      expect(forms.first["data-turbo"]).to eq("false")
      expect(response.body).to include("Continuer avec Google", "Continuer avec Example ID")
    end

    it "offers nothing when no provider is configured" do
      with_providers(ProviderHelpers::PROVIDER_ENV.transform_values { "" }) do
        get new_session_path
      end

      expect(response.parsed_body.css('form[action^="/auth/"]')).to be_empty
    end

    it "offers nothing inside an iOS companion without the auth-session bridge" do
      get new_session_path, headers: { "User-Agent" => "Allure iOS/1.0 Hotwire Native iOS; bridge-components: [topbar]" }

      expect(response.parsed_body.css('form[action^="/auth/"], [data-controller="bridge--auth-session"]')).to be_empty
    end
  end

  describe "a new identity" do
    it "creates a password-less account after the username is confirmed" do
      mock_provider(:google, nickname: "Rider.Example")
      sign_in_with(:google)

      expect(response).to redirect_to(new_onboarding_path)
      follow_redirect!
      expect(response.body).to include("Créer votre compte", "rider@example.test", 'value="rider_example"')

      post onboarding_path, params: { user: { username: "newrider", display_name: "New Rider" } }

      user = User.find_by!(username: "newrider")
      expect(response).to redirect_to(me_url)
      expect(user).to have_attributes(email_address: "rider@example.test", password_digest: nil,
                                      second_factor_required_since: nil)
      expect(user.identities.sole).to have_attributes(provider: "google", issuer: google_issuer, subject: "subject-1")
      expect(user.sessions.sole.auth_method).to eq("provider:google")
      expect(Auth::SecondFactorPolicy.new(user)).to be_satisfied
    end

    it "keeps the username rules" do
      mock_provider(:google)
      sign_in_with(:google)
      post onboarding_path, params: { user: { username: "admin" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(User.where(email_address: "rider@example.test")).to be_empty
    end

    it "expires the pending identity after fifteen minutes" do
      mock_provider(:google)
      sign_in_with(:google)

      travel 16.minutes do
        post onboarding_path, params: { user: { username: "newrider" } }
      end

      expect(response).to redirect_to(new_session_path)
      expect(User.find_by(username: "newrider")).to be_nil
    end

    it "never links an existing account by email" do
      existing = create(:user, email_address: "rider@example.test")
      mock_provider(:google)

      sign_in_with(:google)

      expect(response).to redirect_to(new_session_path)
      expect(flash[:alert]).to include("Un compte utilise déjà cette adresse.")
      expect(existing.identities).to be_empty
    end

    it "answers a taken address exactly like an unknown one while registration is closed" do
      allow(Allure::Registration).to receive(:open?).and_return(false)
      create(:user, email_address: "rider@example.test")
      answers = %w[rider@example.test nobody@example.test].map do |email|
        mock_provider(:google, email:)
        sign_in_with(:google)
        [ response.location, flash[:alert] ]
      end

      expect(answers.uniq.size).to eq(1)
      expect(answers.first.last).to include("Les inscriptions sont fermées")
      expect(answers.first.last).not_to include("utilise déjà")
    end

    it "refuses an unverified email" do
      mock_provider(:google, verified: false)

      sign_in_with(:google)

      expect(flash[:alert]).to include("n&#39;a pas confirmé").or include("n'a pas confirmé")
      expect(session[:pending_identity]).to be_nil
    end

    it "is refused while registration is closed, and accepted with an invitation" do
      allow(Allure::Registration).to receive(:open?).and_return(false)
      mock_provider(:google)

      sign_in_with(:google)
      expect(flash[:alert]).to include("Les inscriptions sont fermées")

      invitation, token = RegistrationInvitation.issue(email_address: "invited@allure.test")
      sign_in_with(:google, invitation_token: token)
      post onboarding_path, params: { user: { username: "invited" } }

      expect(User.find_by!(username: "invited").email_address).to eq("invited@allure.test")
      expect(invitation.reload).to be_accepted
    end

    it "prefers the invitation's display name over the provider's" do
      allow(Allure::Registration).to receive(:open?).and_return(false)
      mock_provider(:google)
      _, token = RegistrationInvitation.issue(email_address: "invited@allure.test", display_name: "Jeanne Martin")

      sign_in_with(:google, invitation_token: token)
      follow_redirect!

      expect(response.body).to include(%(value="Jeanne Martin"))
    end
  end

  describe "a known identity" do
    it "signs in directly, even on an account with a password and an authenticator app" do
      user = create(:user, :with_totp)
      link_identity(user)
      mock_provider(:google)

      sign_in_with(:google)

      expect(response).to redirect_to(me_url)
      expect(user.sessions.sole).to have_attributes(auth_method: "provider:google", second_factor_at: nil)
    end

    it "does not restrict a provider session when the password grace period has ended" do
      user = create(:user, second_factor_required_since: 30.days.ago)
      link_identity(user)
      mock_provider(:google)

      sign_in_with(:google)
      get me_path

      expect(response).to have_http_status(:ok)
      expect(user.sessions.sole).not_to be_enrolment_only
    end

    it "refuses a suspended account" do
      user = create(:user, suspended_at: Time.current)
      link_identity(user)
      mock_provider(:google)

      sign_in_with(:google)

      expect(user.sessions).to be_empty
      expect(flash[:alert]).to include("suspendu")
    end

    it "refuses a generic provider that did not apply the required authentication level" do
      with_providers(ProviderHelpers::PROVIDER_ENV.merge("AUTH_OIDC_REQUIRED_ACR" => "urn:mfa")) do
        user = create(:user)
        link_identity(user, provider: "oidc", issuer: "https://id.example.test")
        mock_provider(:oidc, acr: "urn:password")
        sign_in_with(:oidc)
        expect(user.sessions).to be_empty

        mock_provider(:oidc, acr: "urn:mfa")
        sign_in_with(:oidc)
        expect(user.sessions.sole.auth_method).to eq("provider:oidc")
      end
    end

    it "refuses a generic provider whose sign-in lacks the required authentication method" do
      with_providers(ProviderHelpers::PROVIDER_ENV.merge("AUTH_OIDC_REQUIRED_AMR" => "mfa")) do
        user = create(:user)
        link_identity(user, provider: "oidc", issuer: "https://id.example.test")
        mock_provider(:oidc, amr: [ "pwd" ])
        sign_in_with(:oidc)
        expect(user.sessions).to be_empty
        expect(flash[:alert]).to include("niveau d&#39;authentification").or include("niveau d'authentification")

        mock_provider(:oidc, amr: %w[pwd mfa])
        sign_in_with(:oidc)
        expect(user.sessions.sole.auth_method).to eq("provider:oidc")
      end
    end

    it "takes the provider's authentication time as the session's proof of identity" do
      user = create(:user)
      link_identity(user)
      mock_provider(:google, auth_time: 2.days.ago)

      sign_in_with(:google)

      expect(user.sessions.sole.reauthenticated_at).to be_within(5.seconds).of(2.days.ago)
      get new_settings_api_token_path
      expect(response).to redirect_to(new_reauthentication_path)
    end

    it "never records a proof of identity later than now" do
      user = create(:user)
      link_identity(user)
      mock_provider(:google, auth_time: 1.hour.from_now)

      sign_in_with(:google)

      expect(user.sessions.sole.reauthenticated_at).to be_within(5.seconds).of(Time.current)
    end

    it "never reads the authentication level from an ID token it did not verify" do
      with_providers(ProviderHelpers::PROVIDER_ENV.merge("AUTH_OIDC_REQUIRED_ACR" => "urn:mfa")) do
        user = create(:user)
        link_identity(user, provider: "oidc", issuer: "https://id.example.test")
        mock_provider(:oidc)
        OmniAuth.config.mock_auth[:oidc].credentials.id_token = JSON::JWT.new(acr: "urn:mfa").to_s

        sign_in_with(:oidc)

        expect(user.sessions).to be_empty
        expect(flash[:alert]).to be_present
      end
    end
  end

  describe "the operator" do
    around do |example|
      previous = ENV["INSTANCE_OPERATOR_USERNAME"]
      ENV["INSTANCE_OPERATOR_USERNAME"] = "operator"
      example.run
    ensure
      previous.nil? ? ENV.delete("INSTANCE_OPERATOR_USERNAME") : ENV["INSTANCE_OPERATOR_USERNAME"] = previous
    end

    it "still answers Allure's second factor after the provider" do
      operator = create(:user, :with_totp, username: "operator")
      link_identity(operator)
      mock_provider(:google)

      sign_in_with(:google)
      expect(response).to redirect_to(new_session_challenge_path)

      post session_challenge_path, params: { code: ROTP::TOTP.new(operator.otp_secret).now }
      expect(operator.sessions.sole).to have_attributes(auth_method: "provider:google", second_factor_method: "totp")
    end

    it "is restricted to enrolment without a factor, even password-less" do
      operator = passwordless_user(username: "operator")
      mock_provider(:google)

      sign_in_with(:google)

      expect(response).to redirect_to(settings_security_path)
      expect(operator.sessions.sole).to be_enrolment_only
    end
  end

  describe "linking" do
    let(:user) { create(:user) }

    before { sign_in_as(user) }

    it "links a new identity for a recently re-authenticated account and mails it" do
      mock_provider(:google, email: "other@example.test")

      expect { sign_in_with(:google, intent: "link") }.to have_enqueued_mail(SecurityMailer, :notice)

      expect(response).to redirect_to(settings_security_path)
      expect(user.identities.sole).to have_attributes(provider: "google", email: "other@example.test")
      get settings_security_path
      expect(response.body).to include("Fournisseurs d&#39;identité", "other@example.test", "Associer Apple")
    end

    it "asks for a fresh proof of identity first" do
      mock_provider(:google)

      travel 11.minutes do
        sign_in_with(:google, intent: "link")
      end

      expect(response).to redirect_to(new_reauthentication_path)
      expect(user.identities).to be_empty
    end

    it "refuses an identity linked to another account" do
      link_identity(create(:user))
      mock_provider(:google)

      sign_in_with(:google, intent: "link")

      expect(flash[:alert]).to include("déjà associée à un autre compte")
      expect(user.identities).to be_empty
    end

    it "unlinks an identity while a password remains" do
      identity = link_identity(user)

      delete settings_identity_path(identity)

      expect(response).to redirect_to(settings_security_path)
      expect(user.identities.reload).to be_empty
    end
  end

  describe "a password-less account" do
    let(:user) { passwordless_user }

    before do
      mock_provider(:google)
      user
      sign_in_with(:google)
    end

    it "cannot unlink its only way in" do
      delete settings_identity_path(user.identities.sole)

      expect(flash[:alert]).to include("votre seule façon de vous connecter")
      expect(user.identities.reload.size).to eq(1)
    end

    it "sets a first password, which starts the second-factor grace period" do
      get settings_security_path
      expect(response.body).to include("Définir un mot de passe")

      patch settings_security_password_path, params: {
        user: { password: "first-password-123", password_confirmation: "first-password-123" }
      }

      expect(response).to redirect_to(settings_security_path)
      expect(user.reload.authenticate("first-password-123")).to be_truthy
      expect(user.second_factor_required_since).to be_within(5.seconds).of(Time.current)
      expect(Auth::SecondFactorPolicy.new(user)).to be_grace
    end

    it "re-authenticates through its provider, asked to authenticate the person again" do
      travel 11.minutes do
        get new_reauthentication_path
        expect(response.parsed_body.at_css('form[action="/auth/google?intent=reauthenticate&max_age=0&prompt=login"]'))
          .to be_present

        mock_provider(:google, auth_time: Time.current)
        sign_in_with(:google, intent: "reauthenticate")

        expect(response).to redirect_to(settings_security_path)
        expect(user.sessions.sole.reload).to be_recently_authenticated
      end
    end

    it "refuses a re-authentication the provider did not perform again" do
      travel 11.minutes do
        mock_provider(:google, auth_time: 20.minutes.ago)
        sign_in_with(:google, intent: "reauthenticate")

        expect(response).to redirect_to(settings_security_path)
        expect(flash[:alert]).to include("n&#39;a pas vérifié votre identité").or include("n'a pas vérifié votre identité")
        expect(user.sessions.sole.reload).not_to be_recently_authenticated
      end
    end

    it "trusts a re-authentication by a provider that reports no authentication time" do
      travel 11.minutes do
        mock_provider(:google)
        sign_in_with(:google, intent: "reauthenticate")

        expect(user.sessions.sole.reload).to be_recently_authenticated
      end
    end

    it "cannot sign in with a password" do
      delete session_path
      post session_path, params: { email_address: user.email_address, password: "anything-at-all-1" }

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "is not sent a password reset" do
      expect { Users::PasswordResetJob.perform_now(user.email_address) }
        .not_to(change { ActionMailer::Base.deliveries.count })
    end
  end

  describe "the operator's password setup link" do
    before do
      require "rake"
      Rails.application.load_tasks unless Rake::Task.task_defined?("users:send_password_setup")
      Rake::Task["users:send_password_setup"].reenable
    end

    it "mails a password-less account a link and audits it" do
      user = passwordless_user(username: "nopassword")

      ENV["USERNAME"] = "nopassword"
      expect { Rake::Task["users:send_password_setup"].invoke }
        .to output(/Password setup link sent/).to_stdout
        .and change { ActionMailer::Base.deliveries.count }.by(1)
      expect(AdminEvent.last).to have_attributes(action: "password_setup_sent", subject: user)
    ensure
      ENV.delete("USERNAME")
    end

    it "sets a password that owes a second factor at once" do
      user = passwordless_user

      put password_path(user.password_reset_token),
          params: { user: { password: "first-password-123", password_confirmation: "first-password-123" } }

      expect(response).to redirect_to(new_session_path)
      expect(user.reload.authenticate("first-password-123")).to be_truthy
      expect(Auth::SecondFactorPolicy.new(user)).to be_required
    end
  end

  describe "Sign in with Apple's form post" do
    it "re-posts Apple's fields from this origin without touching the session" do
      post apple_form_post_path, params: { code: "abc", state: "xyz", id_token: "token", user: '{"name":{}}', extra: "x" }

      form = response.parsed_body.at_css("form#apple-return")
      expect(form["action"]).to eq("/auth/apple/return")
      expect(form.css("input").to_h { |input| [ input["name"], input["value"] ] })
        .to eq("code" => "abc", "state" => "xyz", "id_token" => "token", "user" => '{"name":{}}')
      expect(response.headers["Set-Cookie"].to_s).not_to include("_allure_session")
    end

    it "signs in a known Apple identity from the return" do
      user = create(:user)
      link_identity(user, provider: "apple", issuer: Allure::Auth::Providers::APPLE_ISSUER, subject: "apple-sub")
      OmniAuth.config.mock_auth[:apple] = OmniAuth::AuthHash.new(
        provider: "apple", uid: "apple-sub", info: { email: user.email_address, email_verified: true }
      )

      # Apple's answer goes to the form-post page, whose re-post lands on the
      # OmniAuth callback from this origin.
      post "/auth/apple?intent=sign_in"
      expect(URI(response.location).path).to eq(apple_form_post_path)
      post apple_return_path, params: { code: "abc", state: "xyz" }

      expect(user.sessions.sole.auth_method).to eq("provider:apple")
    end
  end

  it "reports a failed round trip" do
    get provider_failure_path(message: "invalid_credentials", strategy: "google")

    expect(response).to redirect_to(new_session_path)
    expect(flash[:alert]).to eq("La connexion par le fournisseur n'a pas abouti. Réessayez.")
  end
end
