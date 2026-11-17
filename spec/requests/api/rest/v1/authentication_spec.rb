# frozen_string_literal: true

require "rails_helper"

RSpec.describe "REST API authentication (docs/dev/API.md)", type: :request do
  let(:user) { create(:user) }

  def problem = response.parsed_body

  it "answers 401 without a token" do
    get "/api/rest/v1/me"

    expect(response).to have_http_status(:unauthorized)
    expect(response.media_type).to eq("application/problem+json")
    expect(response.headers["WWW-Authenticate"]).to start_with("Bearer")
    expect(problem).to include("code" => "missing_token", "status" => 401)
    expect_api_contract
  end

  it "answers 401 for unknown, revoked and expired tokens" do
    revoked, revoked_secret = ApiToken.issue!(user:, name: "R", scopes: %w[read])
    revoked.revoke!(by: "owner")
    expired, expired_secret = ApiToken.issue!(user:, name: "E", scopes: %w[read])
    expired.update_columns(expires_at: 1.second.ago)

    [ "allure_pat_#{'x' * 43}", revoked_secret, expired_secret, "not-a-token" ].each do |secret|
      get "/api/rest/v1/me", headers: { "Authorization" => "Bearer #{secret}" }

      expect(response).to have_http_status(:unauthorized)
      expect(problem["code"]).to eq("invalid_token")
    end
  end

  it "never authenticates with the browser session" do
    sign_in_as(user)

    get "/api/rest/v1/me"

    expect(response).to have_http_status(:unauthorized)
  end

  it "refuses a suspended account" do
    headers = api_headers_for(user)
    user.update_columns(suspended_at: Time.current)

    get "/api/rest/v1/me", headers: headers

    expect(response).to have_http_status(:forbidden)
    expect(problem["code"]).to eq("account_suspended")
    expect_api_contract
  end

  it "refuses an account that owes two-step verification past its grace period" do
    headers = api_headers_for(user)
    user.update_columns(second_factor_required_since: 30.days.ago)

    get "/api/rest/v1/me", headers: headers

    expect(response).to have_http_status(:forbidden)
    expect(problem["code"]).to eq("second_factor_required")
  end

  it "refuses an operation outside the token's scopes" do
    get "/api/rest/v1/workouts", headers: api_headers_for(user, scopes: %w[webhooks])

    expect(response).to have_http_status(:forbidden)
    expect(problem).to include("code" => "insufficient_scope")
    expect(problem["detail"]).to include("read")
    expect_api_contract
  end

  it "records the token's last use" do
    token, secret = ApiToken.issue!(user:, name: "A", scopes: %w[read])

    get "/api/rest/v1/me", headers: { "Authorization" => "Bearer #{secret}" }

    expect(token.reload.last_used_at).to be_within(5.seconds).of(Time.current)
    expect(user.sessions).to be_empty
  end

  it "answers an unknown path with a problem document" do
    get "/api/rest/v1/nothing-here", headers: api_headers_for(user)

    expect(response).to have_http_status(:not_found)
    expect(response.media_type).to eq("application/problem+json")
    expect(problem["code"]).to eq("not_found")
  end

  it "keeps responses out of shared caches" do
    get "/api/rest/v1/me", headers: api_headers_for(user)

    expect(response.headers["Cache-Control"]).to include("private")
  end

  describe "rate limits (docs/dev/API.md)" do
    # The test cache is a null store; this counts as a store would, so the
    # bucket a request lands in can be observed.
    let(:counts) { Hash.new(0) }

    before do
      allow(Api::Rest::V1::BaseController.cache_store).to receive(:increment) do |key, amount = 1, **|
        counts[key] += amount
      end
    end

    it "counts a token's requests in one bucket, whatever the resource" do
      headers = api_headers_for(user, scopes: %w[read webhooks])

      get "/api/rest/v1/me", headers: headers
      expect(response).to have_http_status(:ok)
      expect(counts.size).to eq(1)

      counts.transform_values! { 300 }
      get "/api/rest/v1/workouts", headers: headers
      expect(response).to have_http_status(:too_many_requests)
      expect(response.headers["Retry-After"]).to eq("60")
      expect(problem["code"]).to eq("rate_limited")
      expect_api_contract

      post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "ping" }.to_json,
                   headers: headers.merge("Content-Type" => "application/json")
      expect(response).to have_http_status(:too_many_requests)
    end

    it "counts mutations in a bucket of their own, shared the same way" do
      headers = api_headers_for(user, scopes: %w[write webhooks], "Content-Type" => "application/json")

      post "/api/rest/v1/webhooks", params: { url: "https://hooks.example.com/a", events: %w[workout.created] }.to_json,
                                    headers: headers
      expect(response).to have_http_status(:created)
      expect(counts.size).to eq(2)

      counts.transform_values! { 60 }
      workout = create(:workout, user:)
      patch "/api/rest/v1/workouts/#{workout.to_param}", params: { title: "Encore" }.to_json, headers: headers
      expect(response).to have_http_status(:too_many_requests)
      expect(workout.reload.title).not_to eq("Encore")
    end
  end
end
