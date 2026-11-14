# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Settings: API tokens (PLAN_API.md §4.4, DESIGN.md §20.18)", type: :request do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }

  before { sign_in_as(user) }

  it "lists the account's tokens with their prefix, never their secret" do
    token, secret = ApiToken.issue!(user:, name: "Dashboard", scopes: %w[read import])
    ApiToken.issue!(user: create(:user), name: "Someone else's", scopes: %w[read])

    get settings_api_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Dashboard", token.token_prefix)
    expect(response.body).not_to include(secret, "Someone else's")
    expect(response.body).to include(developers_api_path)
  end

  it "asks for a recent proof of identity before creating a token" do
    Session.last.update!(reauthenticated_at: 1.hour.ago)

    get new_settings_api_token_path

    expect(response).to redirect_to(new_reauthentication_path)
  end

  it "creates a token, shows its secret once, and mails the account" do
    get new_settings_api_token_path
    expect(response.body).to include(ERB::Util.html_escape(I18n.t("settings.api_tokens.new.warning", locale: :fr)))

    expect {
      post settings_api_tokens_path, params: { api_token: { name: "Home dashboard", scopes: %w[read publish],
                                                            expires_in_days: "30" } }
    }.to change(ApiToken, :count).by(1).and have_enqueued_mail(SecurityMailer, :notice)

    token = user.api_tokens.sole
    expect(token.scopes).to eq(%w[read publish])
    expect(token.expires_at).to be_within(1.minute).of(30.days.from_now)
    expect(response).to redirect_to(created_settings_api_tokens_path)

    follow_redirect!
    secret = response.body[/allure_pat_[A-Za-z0-9_-]{43}/]
    expect(ApiToken.authenticate(secret)).to eq(token)
    expect(response.headers["Cache-Control"]).to include("no-store")

    get created_settings_api_tokens_path
    expect(response).to redirect_to(settings_api_path)
  end

  it "creates a token without location for AI assistants unless one is chosen (PLAN_MCP.md §4)" do
    post settings_api_tokens_path, params: { api_token: { name: "Script", scopes: %w[read], expires_in_days: "90" } }

    expect(user.api_tokens.sole.mcp_geometry).to eq("none")
  end

  it "records the chosen location level, says so in the mail, and offers MCP configurations with the secret" do
    get new_settings_api_token_path
    expect(response.body).to include(ERB::Util.html_escape(I18n.t("settings.api_tokens.new.mcp_geometry.warning", locale: :fr)))

    perform_enqueued_jobs do
      post settings_api_tokens_path, params: { api_token: { name: "Local model", scopes: %w[read], expires_in_days: "90",
                                                            mcp_geometry: "raw" } }
    end

    token = user.api_tokens.sole
    expect(token.mcp_geometry).to eq("raw")
    expect(ActionMailer::Base.deliveries.last.text_part.body.to_s)
      .to include(I18n.t("security_mailer.notice.mcp_geometry.raw", locale: user.locale))

    follow_redirect!
    secret = response.body[/allure_pat_[A-Za-z0-9_-]{43}/]
    expect(response.body).to include("#{Allure::Federation.config.base_url}/mcp", "Bearer #{secret}")

    get settings_api_path
    expect(response.body).to include(I18n.t("settings.api.mcp_geometry.raw.badge", locale: :fr))
    expect(response.body).not_to include(secret)
  end

  it "refuses a location level above the instance's ceiling" do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("MCP_GEOMETRY_MAX", "").and_return("filtered")

    get new_settings_api_token_path
    expect(response.body).not_to include('value="raw"')

    post settings_api_tokens_path, params: { api_token: { name: "Too much", scopes: %w[read], expires_in_days: "90",
                                                          mcp_geometry: "raw" } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(ApiToken.count).to eq(0)
  end

  it "re-renders the form when no permission is ticked" do
    post settings_api_tokens_path, params: { api_token: { name: "Nothing", expires_in_days: "90" } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include(ERB::Util.html_escape(I18n.t("activerecord.errors.models.api_token.attributes.scopes.blank", locale: :fr)))
    expect(ApiToken.count).to eq(0)
  end

  it "revokes a token and mails the account" do
    token, secret = ApiToken.issue!(user:, name: "Old script", scopes: %w[read])

    expect { delete settings_api_token_path(token) }.to have_enqueued_mail(SecurityMailer, :notice)

    expect(token.reload).to be_revoked
    expect(token.revoked_by).to eq("owner")
    expect(ApiToken.authenticate(secret)).to be_nil
  end

  it "cannot revoke another account's token" do
    other, = ApiToken.issue!(user: create(:user), name: "Theirs", scopes: %w[read])

    delete settings_api_token_path(other)

    expect(response).to have_http_status(:not_found)
    expect(other.reload).not_to be_revoked
  end

  it "keeps the page out of the iOS companion's settings navigation" do
    headers = { "User-Agent" => "Allure iOS (Hotwire Native iOS; Turbo Native iOS)" }

    get settings_path, headers: headers
    expect(response.body).not_to include(settings_api_path)

    get settings_profile_path, headers: headers
    expect(response.body).not_to include(settings_api_path)
  end
end

RSpec.describe "The API reference page (PLAN_API.md §13)", type: :request do
  it "is members-only" do
    get developers_api_path

    expect(response).to redirect_to(new_session_path)
  end

  it "embeds the reference document in a same-origin frame" do
    sign_in_as(create(:user))

    get developers_api_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(developers_api_reference_path, 'data-controller="api-reference-frame"',
                                     "#{Allure::Federation.config.base_url}/api/rest/v1")
  end

  it "serves the reference document without the application stylesheet, framable by the same origin only" do
    sign_in_as(create(:user))

    get developers_api_reference_path

    expect(response).to have_http_status(:ok)
    expect(response.headers["X-Frame-Options"]).to eq("SAMEORIGIN")
    expect(response.body).to include('id="api-reference"', "/api/rest/v1/openapi.json")
    expect(response.body).not_to include("entrypoints/application")
  end

  it "redirects /developers to the reference" do
    get "/developers"

    expect(response).to redirect_to("/developers/api")
  end
end
