# frozen_string_literal: true

require "rails_helper"

# docs/dev/API.md: the operator's view of an account's tokens and webhooks,
# the audited revocation and disabling, and the API metrics.
RSpec.describe "Admin: API tokens and webhooks" do
  include ActiveJob::TestHelper

  let(:operator) { create(:user, :with_totp, username: "operator") }
  let(:member) { create(:user) }
  let!(:token_pair) { ApiToken.issue!(user: member, name: "Dashboard", scopes: %w[read]) }
  let!(:endpoint) { member.webhook_endpoints.create!(url: "https://hooks.example.com/private/path", events: [ "*" ]) }

  around do |example|
    previous = ENV["INSTANCE_OPERATOR_USERNAME"]
    ENV["INSTANCE_OPERATOR_USERNAME"] = "operator"
    example.run
  ensure
    previous.nil? ? ENV.delete("INSTANCE_OPERATOR_USERNAME") : ENV["INSTANCE_OPERATOR_USERNAME"] = previous
  end

  before { sign_in_as(operator) }

  it "lists the account's tokens by prefix and webhooks by host, never a secret nor a path" do
    get admin_account_path(member)

    expect(response).to have_http_status(:ok)
    token, secret = token_pair
    expect(response.body).to include("Dashboard", token.token_prefix, "hooks.example.com")
    expect(response.body).not_to include(secret, "/private/path", endpoint.secret)
  end

  it "revokes a token, mails the account and audits it" do
    token, secret = token_pair

    expect { post admin_account_api_token_revocation_path(member, token) }.to have_enqueued_mail(SecurityMailer, :notice)

    expect(token.reload.revoked_by).to eq("operator")
    expect(ApiToken.authenticate(secret)).to be_nil
    expect(AdminEvent.where(action: "api_token_revoked", subject: token)).to exist
  end

  it "disables a webhook, notifies the account and audits it" do
    post admin_account_webhook_disabling_path(member, endpoint)

    expect(endpoint.reload.state).to eq("disabled_operator")
    expect(Notification.where(user: member, kind: "webhook_disabled").sole.payload["reason"]).to eq("operator")
    expect(AdminEvent.where(action: "webhook_endpoint_disabled", subject: endpoint).sole.metadata)
      .to include("host" => "hooks.example.com")
  end

  it "answers 404 to a member" do
    sign_in_as(member)
    token, = token_pair

    post admin_account_api_token_revocation_path(member, token)

    expect(response).to have_http_status(:not_found)
    expect(token.reload).not_to be_revoked
  end
end

RSpec.describe "API metrics (docs/dev/API.md)", type: :request do
  around do |example|
    previous = ENV["METRICS_TOKEN"]
    ENV["METRICS_TOKEN"] = "metrics-secret"
    example.run
  ensure
    previous.nil? ? ENV.delete("METRICS_TOKEN") : ENV["METRICS_TOKEN"] = previous
  end

  it "exposes token, webhook and request counts without hosts, accounts or tokens" do
    member = create(:user)
    _token, secret = ApiToken.issue!(user: member, name: "Dashboard", scopes: %w[read])
    member.webhook_endpoints.create!(url: "https://hooks.example.com/", events: [ "*" ])
    get "/api/rest/v1/workouts", headers: { "Authorization" => "Bearer #{secret}" }
    get "/api/rest/v1/workouts"
    allow(Metrics::Cache).to receive(:fetch).and_return(Metrics::Snapshot.new.call)

    get "/metrics", headers: { "Authorization" => "Bearer metrics-secret" }

    body = response.body
    expect(body).to match(/^allure_api_tokens\{status="active"\} 1(\.0)?$/)
    expect(body).to match(/^allure_webhook_endpoints\{status="active"\} 1(\.0)?$/)
    expect(body).to match(/^allure_api_requests_total\{scope="read",status_class="2xx"\} \d/)
    expect(body).to match(/^allure_api_requests_total\{scope="any",status_class="4xx"\} \d/)
    expect(body).to include("allure_webhook_delivery_oldest_pending_seconds")
    expect(body).not_to include("hooks.example.com", member.username, secret)
  end
end
