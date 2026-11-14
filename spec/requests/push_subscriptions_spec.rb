# frozen_string_literal: true

require "rails_helper"

# PLAN_PUSH.md §5–§6: the current session's subscription, the native
# unsubscribe, and the « Sur cet iPhone » card.
RSpec.describe "Push subscriptions" do
  let(:user) { create(:user) }
  let(:device) { PushHelpers::Device.generate }
  let(:companion) { "Allure iOS (Hotwire Native iOS; bridge-components: [push topbar])" }
  let(:json) { { "Accept" => "application/json" } }

  around { |example| with_push_env { example.run } }

  def current_session = user.sessions.order(:id).last

  def subscribe(endpoint: relay_endpoint, **extra)
    post settings_push_subscription_path,
         params: { endpoint:, p256dh: device.p256dh, auth: device.auth, **extra }, as: :json, headers: json
  end

  describe "settings" do
    before { sign_in_as(user) }

    it "creates the subscription of the current session and answers its state" do
      endpoint = relay_endpoint
      expect { subscribe(endpoint:) }.to change(PushSubscription, :count).by(1)

      expect(response).to have_http_status(:created)
      subscription = PushSubscription.sole
      expect(subscription.session).to eq(current_session)
      expect(subscription.user).to eq(user)
      expect(response.parsed_body).to eq("status" => "on", "hide_content" => false,
                                         "endpoint_digest" => Digest::SHA256.hexdigest(endpoint))
    end

    it "replaces the session's subscription on a new registration" do
      subscribe
      second = relay_endpoint
      expect { subscribe(endpoint: second, hide_content: true) }.not_to change(PushSubscription, :count)

      expect(PushSubscription.sole.endpoint).to eq(second)
      expect(PushSubscription.sole).to be_hide_content
    end

    it "refuses an endpoint outside the relay list or malformed keys" do
      subscribe(endpoint: "https://evil.example/v1/push/abc")
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to include("error" => "invalid", "fields" => [ "endpoint" ])

      post settings_push_subscription_path, params: { endpoint: relay_endpoint, p256dh: "x", auth: "y" }, as: :json
      expect(response).to have_http_status(:unprocessable_content)
      expect(PushSubscription.count).to eq(0)
    end

    it "keeps an earlier registration when the new one is invalid" do
      endpoint = relay_endpoint
      older = create_push_subscription(session: user.sessions.create!(auth_method: "password"), endpoint:)

      subscribe(endpoint:, p256dh: "x", auth: "y")

      expect(response).to have_http_status(:unprocessable_content)
      expect(PushSubscription.sole).to eq(older)
    end

    it "replaces this account's earlier registration of the same endpoint" do
      endpoint = relay_endpoint
      signed_in = current_session
      older = create_push_subscription(session: user.sessions.create!(auth_method: "password"), endpoint:)

      expect { subscribe(endpoint:) }.not_to change(PushSubscription, :count)

      expect(PushSubscription.exists?(older.id)).to be(false)
      expect(PushSubscription.sole).to have_attributes(session_id: signed_in.id, endpoint:)
    end

    it "never replaces another account's registration" do
      endpoint = relay_endpoint
      other_user = create(:user)
      other = create_push_subscription(session: other_user.sessions.create!(auth_method: "password"), endpoint:)

      subscribe(endpoint:)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to include("error" => "invalid", "fields" => [ "endpoint" ])
      expect(PushSubscription.sole).to eq(other)
    end

    it "toggles hiding the content of the session's own subscription only" do
      subscribe
      other_user = create(:user)
      other = create_push_subscription(session: other_user.sessions.create!(auth_method: "password"))

      patch settings_push_subscription_path, params: { hide_content: true }, as: :json, headers: json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include("status" => "on", "hide_content" => true)
      expect(PushSubscription.find_by(session: current_session)).to be_hide_content
      expect(other.reload).not_to be_hide_content
    end

    it "deletes only the session's own subscription" do
      subscribe
      sibling = create_push_subscription(session: user.sessions.create!(auth_method: "password"))

      delete settings_push_subscription_path, as: :json, headers: json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq("status" => "off")
      expect(PushSubscription.all).to contain_exactly(sibling)
    end

    it "answers 404 for an update without a subscription" do
      patch settings_push_subscription_path, params: { hide_content: true }, as: :json, headers: json

      expect(response).to have_http_status(:not_found)
    end

    it "does not exist while push is unconfigured" do
      with_push_env(push_env("VAPID_PUBLIC_KEY" => nil)) do
        subscribe
        expect(response).to have_http_status(:not_found)
        delete settings_push_subscription_path, as: :json
        expect(response).to have_http_status(:not_found)
      end
      expect(PushSubscription.count).to eq(0)
    end

    it "requires the CSRF token like every other session write" do
      ActionController::Base.allow_forgery_protection = true
      subscribe
      expect(response).to have_http_status(:unprocessable_content)
      expect(PushSubscription.count).to eq(0)
    ensure
      ActionController::Base.allow_forgery_protection = false
    end

    it "goes away when the session signs out" do
      subscribe

      expect { delete session_path }.to change(PushSubscription, :count).by(-1)
    end
  end

  it "requires a signed-in session" do
    subscribe

    expect(response).to have_http_status(:unauthorized).or have_http_status(:found)
    expect(PushSubscription.count).to eq(0)
  end

  describe "POST /push/unsubscribe" do
    let(:session) { user.sessions.create!(auth_method: "password") }
    let!(:subscription) { create_push_subscription(session:, device:) }

    it "deletes the subscription for the device's own auth secret, without a session" do
      post push_unsubscribe_path, params: { endpoint: subscription.endpoint, auth: device.auth }, as: :json

      expect(response).to have_http_status(:no_content)
      expect(PushSubscription.exists?(subscription.id)).to be(false)
    end

    it "answers 204 and keeps the subscription for a wrong proof or an unknown endpoint" do
      post push_unsubscribe_path,
           params: { endpoint: subscription.endpoint, auth: Allure::Push::Config.encode(SecureRandom.random_bytes(16)) },
           as: :json
      expect(response).to have_http_status(:no_content)

      post push_unsubscribe_path, params: { endpoint: subscription.endpoint }, as: :json
      expect(response).to have_http_status(:no_content)

      post push_unsubscribe_path, params: { endpoint: relay_endpoint, auth: device.auth }, as: :json
      expect(response).to have_http_status(:no_content)
      expect(PushSubscription.exists?(subscription.id)).to be(true)
    end

    it "accepts the request without a CSRF token" do
      ActionController::Base.allow_forgery_protection = true
      post push_unsubscribe_path, params: { endpoint: subscription.endpoint, auth: device.auth }, as: :json

      expect(response).to have_http_status(:no_content)
      expect(PushSubscription.exists?(subscription.id)).to be(false)
    ensure
      ActionController::Base.allow_forgery_protection = false
    end
  end

  describe "the « Sur cet iPhone » card" do
    before { sign_in_as(user) }

    it "renders for a companion that registers the push component" do
      get settings_notifications_path, headers: { "User-Agent" => companion }

      card = response.parsed_body.at_css('[data-controller="bridge--push"]')
      expect(card).to be_present
      expect(card["data-bridge--push-url-value"]).to eq(settings_push_subscription_path)
      expect(card["data-bridge--push-server-digest-value"]).to eq("")
      expect(card["data-bridge--push-vapid-key-value"]).to eq(PushHelpers::VAPID[:public_key])
      expect(card.text).to include("Sur cet iPhone", "Recevoir sur cet iPhone", "Masquer le contenu",
                                   "Le contenu est chiffré pour cet iPhone ; ni le relais d'Allure ni Apple ne peuvent le lire.",
                                   "Cette version de l'app ne peut pas recevoir de notifications.",
                                   "Notifications refusées dans les Réglages de l'iPhone.")
    end

    it "carries the digest of this session's subscription and its content choice" do
      subscription = create_push_subscription(session: current_session, hide_content: true)

      get settings_notifications_path, headers: { "User-Agent" => companion }

      card = response.parsed_body.at_css('[data-controller="bridge--push"]')
      expect(card["data-bridge--push-server-digest-value"]).to eq(subscription.endpoint_digest)
      expect(card.at_css('[data-bridge--push-target="hide"]')["checked"]).to be_present
      expect(response.body).not_to include(subscription.endpoint)
    end

    it "speaks English to an English account" do
      user.update!(locale: "en")

      get settings_notifications_path, headers: { "User-Agent" => companion }

      expect(response.body).to include("On this iPhone", "Receive on this iPhone", "Hide the content")
    end

    it "is absent from a browser, an older companion, and an unconfigured instance" do
      get settings_notifications_path
      expect(response.body).not_to include("bridge--push")

      get settings_notifications_path, headers: { "User-Agent" => "Allure iOS (Hotwire Native iOS; bridge-components: [topbar])" }
      expect(response.body).not_to include("bridge--push")

      with_push_env(push_env("VAPID_SUBJECT" => nil)) do
        get settings_notifications_path, headers: { "User-Agent" => companion }
      end
      expect(response.body).not_to include("bridge--push")
    end
  end
end
