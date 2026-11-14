# frozen_string_literal: true

require "rails_helper"

RSpec.describe PushSubscription do
  let(:user) { create(:user) }
  let(:session) { user.sessions.create!(auth_method: "password", user_agent: "Hotwire Native iOS") }
  let(:device) { PushHelpers::Device.generate }

  around { |example| with_push_env { example.run } }

  def build_subscription(**attributes)
    described_class.new(user:, session:, endpoint: relay_endpoint, p256dh: device.p256dh, auth: device.auth, **attributes)
  end

  it "stores the endpoint and the auth secret encrypted, and finds a row by its endpoint" do
    subscription = build_subscription
    subscription.save!

    row = described_class.connection.select_one("SELECT endpoint, auth, endpoint_digest FROM push_subscriptions")
    expect(row["endpoint"]).not_to include("push.allure.rocks")
    expect(row["auth"]).not_to eq(device.auth)
    expect(row["endpoint_digest"]).to eq(Digest::SHA256.hexdigest(subscription.endpoint))
    expect(described_class.find_by_endpoint(subscription.endpoint)).to eq(subscription)
    expect(described_class.find_by_endpoint("")).to be_nil
  end

  it "accepts keys with padding or the standard alphabet and stores them canonical" do
    padded = Base64.urlsafe_encode64(Allure::Push::Config.decode(device.auth))
    subscription = build_subscription(auth: padded)

    expect(subscription).to be_valid
    expect(subscription.auth).to eq(device.auth)
  end

  it "only accepts an endpoint on a listed relay" do
    expect(build_subscription(endpoint: "https://evil.example/v1/push/abc")).not_to be_valid
    expect(build_subscription(endpoint: "http://push.allure.rocks/v1/push/abc")).not_to be_valid
    expect(build_subscription(endpoint: "https://user:pw@push.allure.rocks/v1/push/abc")).not_to be_valid
    expect(build_subscription(endpoint: "https://push.allure.rocks:8443/v1/push/abc")).not_to be_valid
    expect(build_subscription(endpoint: "not a url")).not_to be_valid

    with_push_env(push_env("PUSH_RELAY_ORIGINS" => "https://relay.example:8443")) do
      expect(build_subscription(endpoint: "https://relay.example:8443/v1/push/abc")).to be_valid
      expect(build_subscription(endpoint: relay_endpoint)).not_to be_valid
    end
  end

  it "checks the device's public key and auth secret" do
    expect(build_subscription(p256dh: Allure::Push::Config.encode("\x04".b + ("a" * 64)))).not_to be_valid
    expect(build_subscription(p256dh: Allure::Push::Config.encode(SecureRandom.random_bytes(33)))).not_to be_valid
    expect(build_subscription(p256dh: "***")).not_to be_valid
    expect(build_subscription(auth: Allure::Push::Config.encode(SecureRandom.random_bytes(15)))).not_to be_valid
    expect(build_subscription(auth: "")).not_to be_valid
  end

  it "belongs to the session's own account" do
    expect(build_subscription(user: create(:user))).not_to be_valid
  end

  it "holds one subscription per session and per endpoint" do
    first = build_subscription.tap(&:save!)

    expect(build_subscription).not_to be_valid
    other_session = user.sessions.create!(auth_method: "password")
    duplicate = described_class.new(user:, session: other_session, endpoint: first.endpoint, p256dh: device.p256dh,
                                    auth: device.auth)
    expect(duplicate).not_to be_valid
  end

  it "goes with its session and with its account" do
    build_subscription.save!
    expect { session.destroy! }.to change(described_class, :count).by(-1)

    other = user.sessions.create!(auth_method: "password")
    described_class.create!(user:, session: other, endpoint: relay_endpoint, p256dh: device.p256dh, auth: device.auth)
    expect { Session.where(id: other.id).delete_all }.to change(described_class, :count).by(-1)
  end

  it "counts consecutive failures and drops itself at the tenth" do
    subscription = build_subscription.tap(&:save!)

    9.times { expect(subscription.record_failure!).to be(false) }
    expect(subscription.reload.failure_count).to eq(9)
    subscription.record_success!
    expect(subscription.reload.failure_count).to eq(0)
    expect(subscription.last_success_at).to be_present

    9.times { subscription.record_failure! }
    expect(subscription.record_failure!).to be(true)
    expect(described_class.exists?(subscription.id)).to be(false)
  end
end
