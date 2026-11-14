# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Settings: webhooks (DESIGN.md §20.18)", type: :request do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }

  before { sign_in_as(user) }

  def create_webhook(events: %w[workout.created])
    post settings_webhooks_path, params: { webhook_endpoint: { url: "https://hooks.example.com/allure", description: "Home",
                                                               events: } }
  end

  it "adds a webhook, shows its secret once, then lists it" do
    get new_settings_webhook_path
    expect(response.body).to include(ERB::Util.html_escape(I18n.t("settings.webhooks.form.warning", locale: :fr)))

    create_webhook
    endpoint = user.webhook_endpoints.sole
    expect(response).to redirect_to(secret_settings_webhook_path(endpoint))

    follow_redirect!
    expect(response.body).to include(endpoint.secret)
    expect(response.headers["Cache-Control"]).to include("no-store")

    get secret_settings_webhook_path(endpoint)
    expect(response).to redirect_to(settings_webhook_path(endpoint))

    get settings_api_path
    expect(response.body).to include("hooks.example.com/allure", I18n.t("settings.webhooks.states.active", locale: :fr))
    expect(response.body).not_to include(endpoint.secret)
  end

  it "re-renders the form with the refusal of an unsafe address" do
    resolve_webhook_hosts_to("192.168.1.10")

    create_webhook

    expect(response).to have_http_status(:unprocessable_content)
    expect(WebhookEndpoint.count).to eq(0)
  end

  it "pauses and re-enables, pings, renews the secret and deletes" do
    create_webhook
    endpoint = user.webhook_endpoints.sole

    patch toggle_settings_webhook_path(endpoint)
    expect(endpoint.reload.state).to eq("paused")
    patch toggle_settings_webhook_path(endpoint)
    expect(endpoint.reload.state).to eq("active")

    post ping_settings_webhook_path(endpoint)
    expect(WebhookEvent.sole.event_type).to eq("ping")

    old = endpoint.secret
    post rotate_secret_settings_webhook_path(endpoint)
    expect(response).to redirect_to(secret_settings_webhook_path(endpoint))
    expect(endpoint.reload.secret).not_to eq(old)

    delete settings_webhook_path(endpoint)
    expect(WebhookEndpoint.count).to eq(0)
  end

  it "lists the deliveries and redelivers one, and serves the live fragment while one is pending" do
    create_webhook
    endpoint = user.webhook_endpoints.sole
    Webhooks::Management.ping!(endpoint)
    delivery = WebhookDelivery.sole

    get settings_webhook_path(endpoint)
    expect(response.body).to include("ping", 'data-controller="live-frame"')

    get settings_webhook_path(endpoint), headers: { "Turbo-Frame" => "webhook-deliveries" }
    expect(response.body).not_to include("<html")
    expect(response.body).not_to include("data-live-frame-done")

    delivery.update!(status: "succeeded", attempts: 1, last_status_code: 200)
    get settings_webhook_path(endpoint), headers: { "Turbo-Frame" => "webhook-deliveries" }
    expect(response.body).to include("data-live-frame-done")

    post settings_webhook_delivery_redelivery_path(delivery)
    expect(WebhookDelivery.where(redelivery_of: delivery)).to exist
  end

  it "never reaches another account's webhook" do
    other = create(:user).webhook_endpoints.create!(url: "https://theirs.example.com/", events: [ "*" ])

    get settings_webhook_path(other)
    expect(response).to have_http_status(:not_found)

    delete settings_webhook_path(other)
    expect(other.reload).to be_present
  end
end

RSpec.describe "Webhooks: the web edit announces what changed", type: :request do
  let(:user) { create(:user) }

  it "names only the fields really changed, an empty field over nothing being no change" do
    user.webhook_endpoints.create!(url: "https://hooks.example.com/", events: %w[workout.updated])
    workout = create(:workout, user:, title: "Before", description: nil, notes: nil)
    sign_in_as(user)

    patch workout_path(workout), params: { workout: { title: "After", description: "", notes: "", commute: "0" } }

    expect(WebhookEvent.sole.payload["changed"]).to eq(%w[title])
  end
end
