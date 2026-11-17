# frozen_string_literal: true

require "rails_helper"

# docs/dev/AUTH.md: the iOS companion signs in through a provider in its
# system browser, which hands the verified answer back to the app's web view
# through a single-use token bound to the app's PKCE challenge. In these specs
# one integration session plays both the system browser and the web view.
RSpec.describe "iOS companion provider handoff" do
  include ActiveSupport::Testing::TimeHelpers

  around { |example| with_providers { example.run } }

  let(:companion) { { "User-Agent" => "Allure iOS/1.0 Hotwire Native iOS; bridge-components: [topbar auth-session]" } }
  let(:verifier) { "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk" }
  let(:challenge) { SessionHandoff.challenge_for(verifier) }

  def link_identity(user, provider: "google", issuer: Allure::Auth::Providers::GOOGLE_ISSUER)
    user.identities.create!(provider:, issuer:, subject: "subject-1", email: user.email_address,
                            email_verified: true, linked_at: Time.current)
  end

  # The system browser: the start page posts to OmniAuth, whose test-mode
  # callback answers the app's scheme with the token.
  def browser_round_trip(provider = :google, **params)
    get companion_provider_start_path(provider:, code_challenge: challenge, **params)
    action = response.parsed_body.at_css("form#provider-start")["action"]
    post action
    get URI(response.location).request_uri
    response.location
  end

  def token_from(location) = Rack::Utils.parse_query(URI(location).query)["token"]

  it "computes the RFC 7636 S256 challenge" do
    expect(challenge).to eq("E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
  end

  describe "the sign-in page in the companion" do
    it "starts each provider through the bridge instead of a form" do
      get new_session_path, headers: companion

      buttons = response.parsed_body.css('[data-controller="bridge--auth-session"]')
      expect(buttons.map { |button| button["data-bridge--auth-session-start-url-value"] })
        .to eq(%w[google apple oidc].map { |name| "http://allure.test:3001/auth/ios/#{name}?intent=sign_in" })
      expect(buttons.first["data-bridge--auth-session-handoff-url-value"]).to eq("/session/handoff")
      expect(response.parsed_body.css('form[action^="/auth/"]')).to be_empty
    end

    it "hides Google where Sign in with Apple is not offered" do
      env = ProviderHelpers::PROVIDER_ENV.merge("AUTH_APPLE_SERVICES_ID" => "")
      with_providers(env) { get new_session_path, headers: companion }

      starts = response.parsed_body.css('[data-controller="bridge--auth-session"]')
                       .map { |button| button["data-bridge--auth-session-start-url-value"] }
      expect(starts).to eq([ "http://allure.test:3001/auth/ios/oidc?intent=sign_in" ])
    end
  end

  describe "the start page" do
    it "posts the request phase with the challenge, the intent and this browser's token" do
      get companion_provider_start_path(provider: "google", code_challenge: challenge, intent: "link",
                                        prompt: "login", invitation_token: "inv")

      form = response.parsed_body.at_css("form#provider-start")
      expect(form["action"]).to eq("/auth/google?client=ios&code_challenge=#{challenge}" \
                                   "&intent=link&invitation_token=inv&prompt=login")
      expect(form.at_css('input[name="authenticity_token"]')["value"]).to be_present
      expect(response.headers["Cache-Control"]).to eq("no-store")
    end

    it "refuses a start from another site, and accepts the sign-in sheet's direct load" do
      get companion_provider_start_path(provider: "google", code_challenge: challenge),
          headers: { "Sec-Fetch-Site" => "cross-site" }
      expect(response).to have_http_status(:forbidden)

      get companion_provider_start_path(provider: "google", code_challenge: challenge),
          headers: { "Sec-Fetch-Site" => "none" }
      expect(response).to have_http_status(:ok)
    end

    it "refuses a missing challenge and an unknown provider" do
      get companion_provider_start_path(provider: "google", code_challenge: "short")
      expect(response).to have_http_status(:bad_request)

      get companion_provider_start_path(provider: "facebook", code_challenge: challenge)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "the round trip" do
    it "hands a known identity to the app, which signs in in its web view" do
      user = create(:user)
      link_identity(user)
      mock_provider(:google, email: user.email_address)

      location = browser_round_trip
      expect(location).to start_with("allure://auth/handoff?token=")
      expect(user.sessions).to be_empty

      post session_handoff_path, params: { token: token_from(location), verifier: }

      expect(response).to redirect_to(me_url)
      expect(user.sessions.sole.auth_method).to eq("provider:google")
      expect(SessionHandoff.count).to eq(0)
    end

    it "opens account creation in the web view for a new identity" do
      mock_provider(:google, nickname: "rider")

      post session_handoff_path, params: { token: token_from(browser_round_trip), verifier: }

      expect(response).to redirect_to(new_onboarding_path)
      post onboarding_path, params: { user: { username: "rider" } }
      expect(User.find_by!(username: "rider").sessions.sole.auth_method).to eq("provider:google")
    end

    it "answers a refusal in the web view with its statement" do
      create(:user, email_address: "rider@example.test")
      mock_provider(:google)

      post session_handoff_path, params: { token: token_from(browser_round_trip), verifier: }

      expect(response).to redirect_to(new_session_path)
      expect(flash[:alert]).to include("Un compte utilise déjà cette adresse.")
    end

    it "links an identity to the account signed in in the web view" do
      user = create(:user)
      sign_in_as(user)
      mock_provider(:google, email: "other@example.test")

      post session_handoff_path, params: { token: token_from(browser_round_trip(intent: "link")), verifier: }

      expect(response).to redirect_to(settings_security_path)
      expect(user.identities.sole.email).to eq("other@example.test")
    end

    it "hands off only a round trip started on the start page" do
      mock_provider(:google)

      post "/auth/google?client=ios&code_challenge=#{challenge}"
      get URI(response.location).request_uri

      expect(response.location).to eq("allure://auth/handoff?status=failed")
      expect(SessionHandoff.count).to eq(0)
    end

    it "hands off only the challenge the start page was opened with" do
      mock_provider(:google)
      other = SessionHandoff.challenge_for("x" * 43)

      get companion_provider_start_path(provider: "google", code_challenge: challenge)
      post "/auth/google?client=ios&code_challenge=#{other}"
      get URI(response.location).request_uri

      expect(response.location).to eq("allure://auth/handoff?status=failed")
      expect(SessionHandoff.count).to eq(0)
    end

    it "carries the verified authentication level through the handoff, not the ID token" do
      with_providers(ProviderHelpers::PROVIDER_ENV.merge("AUTH_OIDC_REQUIRED_ACR" => "urn:mfa")) do
        user = create(:user)
        link_identity(user, provider: "oidc", issuer: "https://id.example.test")
        mock_provider(:oidc, email: user.email_address, acr: "urn:mfa")

        location = browser_round_trip(:oidc)
        payload = JSON.parse(SessionHandoff.sole.payload)
        expect(payload.dig("auth", "extra", "raw_info", "acr")).to eq("urn:mfa")
        expect(payload.dig("auth", "credentials")).to be_nil

        post session_handoff_path, params: { token: token_from(location), verifier: }
        expect(user.sessions.sole.auth_method).to eq("provider:oidc")
      end
    end

    it "carries the provider's authentication time and methods, which the web view's session takes" do
      user = create(:user)
      link_identity(user)
      authenticated = 3.days.ago.change(usec: 0)
      mock_provider(:google, email: user.email_address, amr: %w[pwd mfa], auth_time: authenticated)

      location = browser_round_trip(:google)
      payload = JSON.parse(SessionHandoff.sole.payload)
      expect(payload.dig("auth", "extra", "raw_info", "amr")).to eq(%w[pwd mfa])
      expect(payload.dig("auth", "extra", "raw_info", "auth_time")).to eq(authenticated.to_i)

      post session_handoff_path, params: { token: token_from(location), verifier: }
      expect(user.sessions.sole.reauthenticated_at).to eq(authenticated)
    end

    it "sends a provider failure back to the app" do
      get companion_provider_start_path(provider: "google", code_challenge: challenge)
      get provider_failure_path(message: "invalid_credentials", strategy: "google")

      expect(response.location).to eq("allure://auth/handoff?status=failed")
    end
  end

  describe "redeeming a token" do
    let(:user) { create(:user).tap { |user| link_identity(user) } }
    let(:token) do
      mock_provider(:google, email: user.email_address)
      token_from(browser_round_trip)
    end

    it "needs the app's verifier, and a wrong one spends the token" do
      post session_handoff_path, params: { token:, verifier: "x" * 43 }
      expect(response).to redirect_to(new_session_path)
      expect(flash[:alert]).to eq("La connexion par le fournisseur n'a pas abouti. Réessayez.")

      post session_handoff_path, params: { token:, verifier: }
      expect(user.sessions).to be_empty
    end

    it "is single use" do
      post session_handoff_path, params: { token:, verifier: }
      delete session_path

      post session_handoff_path, params: { token:, verifier: }
      expect(user.sessions).to be_empty
    end

    it "expires after a minute" do
      token
      travel 61.seconds do
        post session_handoff_path, params: { token:, verifier: }
      end

      expect(user.sessions).to be_empty
    end

    it "is answered without a token when the app reports a failure" do
      post session_handoff_path

      expect(response).to redirect_to(new_session_path)
      expect(flash[:alert]).to eq("La connexion par le fournisseur n'a pas abouti. Réessayez.")
    end
  end

  it "keeps the provider's answer encrypted at rest" do
    mock_provider(:google, email: "secret@example.test")
    browser_round_trip

    raw = SessionHandoff.connection.select_value("SELECT payload FROM session_handoffs")
    expect(raw).not_to include("secret@example.test")
  end

  it "sweeps uncollected handoffs with expired sessions" do
    SessionHandoff.issue!(code_challenge: challenge, payload: {}, now: 2.minutes.ago)
    SessionHandoff.issue!(code_challenge: challenge, payload: {})

    Users::PruneExpiredSessionsJob.perform_now

    expect(SessionHandoff.count).to eq(1)
  end
end
