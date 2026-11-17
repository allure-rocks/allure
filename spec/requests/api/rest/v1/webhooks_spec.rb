# frozen_string_literal: true

require "rails_helper"

RSpec.describe "REST API webhooks (docs/dev/API.md)", type: :request do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }
  let(:headers) { api_headers_for(user, scopes: %w[webhooks], "Content-Type" => "application/json") }

  def create_webhook(body = { url: "https://hooks.example.com/allure", events: %w[workout.created] })
    post("/api/rest/v1/webhooks", params: body.to_json, headers:)
    response.parsed_body
  end

  it "creates an endpoint and shows its secret once" do
    body = create_webhook

    expect(response).to have_http_status(:created)
    expect_api_contract
    endpoint = user.webhook_endpoints.sole
    expect(body).to include("id" => endpoint.to_param, "state" => "active", "secret" => endpoint.secret)
    expect(response.headers["Location"]).to end_with("/api/rest/v1/webhooks/#{endpoint.to_param}")

    get "/api/rest/v1/webhooks/#{endpoint.to_param}", headers: headers
    expect(response.parsed_body).not_to have_key("secret")
    expect(response.body).not_to include(endpoint.secret)
    expect_api_contract
  end

  it "replays a kept secret without keeping it in clear" do
    keyed = headers.merge("Idempotency-Key" => "hook-1")
    body = { url: "https://hooks.example.com/allure", events: %w[workout.created] }.to_json

    post "/api/rest/v1/webhooks", params: body, headers: keyed
    secret = response.parsed_body.fetch("secret")
    expect(secret).to start_with(WebhookEndpoint::SECRET_PREFIX)

    kept = ApiIdempotencyKey.sole
    expect(kept.response_body).to include(secret)
    raw = ApiIdempotencyKey.connection.select_value("SELECT response_body FROM api_idempotency_keys WHERE id = #{kept.id}")
    expect(raw).not_to include(secret)
    expect(raw).not_to include(WebhookEndpoint::SECRET_PREFIX)

    post "/api/rest/v1/webhooks", params: body, headers: keyed
    expect(response).to have_http_status(:created)
    expect(response.headers["Idempotency-Replayed"]).to eq("true")
    expect(response.parsed_body["secret"]).to eq(secret)
    expect(user.webhook_endpoints.count).to eq(1)

    id = response.parsed_body["id"]
    post "/api/rest/v1/webhooks/#{id}/secret_rotation", headers: headers.merge("Idempotency-Key" => "rotate-1")
    rotated = response.parsed_body.fetch("secret")
    raw = ApiIdempotencyKey.connection.select_value("SELECT string_agg(response_body, '') FROM api_idempotency_keys")
    expect(raw).not_to include(rotated)
  end

  it "refuses an unsafe address, an unknown event and unknown fields" do
    resolve_webhook_hosts_to("10.1.2.3")

    create_webhook({ url: "https://internal.example.com/", events: %w[workout.exploded], secret: "mine" })

    expect(response).to have_http_status(:unprocessable_content)
    expect_api_contract(request: false)
    expect(response.parsed_body["errors"].pluck("field")).to contain_exactly("secret")

    create_webhook({ url: "https://internal.example.com/", events: %w[workout.exploded] })
    expect(response.parsed_body["errors"].pluck("field", "code")).to contain_exactly(%w[url unsafe], %w[events inclusion])
  end

  it "updates, pauses and re-enables an endpoint the system disabled" do
    id = create_webhook["id"]
    endpoint = user.webhook_endpoints.sole
    endpoint.disable!("failing")

    patch "/api/rest/v1/webhooks/#{id}", params: { active: true, events: [ "*" ] }.to_json, headers: headers

    expect(response).to have_http_status(:ok)
    expect_api_contract
    expect(endpoint.reload).to have_attributes(state: "active", events: [ "*" ], consecutive_failures: 0)

    patch "/api/rest/v1/webhooks/#{id}", params: { active: false }.to_json, headers: headers
    expect(response.parsed_body["state"]).to eq("paused")
  end

  it "pings, rotates the secret, lists deliveries and redelivers" do
    id = create_webhook["id"]
    endpoint = user.webhook_endpoints.sole
    old_secret = endpoint.secret

    post "/api/rest/v1/webhooks/#{id}/ping", headers: headers
    expect(response).to have_http_status(:accepted)
    expect_api_contract
    expect(WebhookEvent.sole.event_type).to eq("ping")

    post "/api/rest/v1/webhooks/#{id}/secret_rotation", headers: headers
    expect(response.parsed_body["secret"]).to eq(endpoint.reload.secret)
    expect(endpoint.signing_secrets).to eq([ endpoint.secret, old_secret ])

    get "/api/rest/v1/webhooks/#{id}/deliveries", headers: headers
    expect_api_contract
    delivery = response.parsed_body["data"].sole
    expect(delivery["event"]).to include("type" => "ping", "id" => start_with("evt_"))

    post "/api/rest/v1/webhook_deliveries/#{delivery['id']}/redelivery", headers: headers
    expect(response).to have_http_status(:accepted)
    expect(response.parsed_body["redelivery_of_id"]).to eq(delivery["id"])
    expect(WebhookDelivery.count).to eq(2)
  end

  it "answers webhook_inactive when pinging a paused endpoint" do
    id = create_webhook["id"]
    user.webhook_endpoints.sole.update!(active: false)

    post "/api/rest/v1/webhooks/#{id}/ping", headers: headers

    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body["code"]).to eq("webhook_inactive")
  end

  it "deletes an endpoint with its deliveries, and never reaches another account's" do
    id = create_webhook["id"]
    other = create(:user).webhook_endpoints.create!(url: "https://theirs.example.com/", events: [ "*" ])

    delete "/api/rest/v1/webhooks/#{other.to_param}", headers: headers
    expect(response).to have_http_status(:not_found)

    delete "/api/rest/v1/webhooks/#{id}", headers: headers
    expect(response).to have_http_status(:no_content)
    expect(WebhookEndpoint.where(user:)).to be_empty
  end

  it "needs the webhooks scope" do
    get "/api/rest/v1/webhooks", headers: api_headers_for(user, scopes: %w[read])

    expect(response.parsed_body["code"]).to eq("insufficient_scope")
  end

  it "announces an API edit with the fields it changed" do
    create_webhook({ url: "https://hooks.example.com/", events: %w[workout.updated] })
    workout = create(:workout, user:)

    patch "/api/rest/v1/workouts/#{workout.to_param}", params: { title: "New", commute: true }.to_json,
                                                       headers: api_headers_for(user, scopes: %w[write], "Content-Type" => "application/json")

    expect(WebhookEvent.where(event_type: "workout.updated").sole.payload["changed"]).to eq(%w[commute title])
  end
end
