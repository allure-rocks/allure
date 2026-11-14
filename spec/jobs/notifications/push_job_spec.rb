# frozen_string_literal: true

require "rails_helper"

RSpec.describe Notifications::PushJob do
  include ActiveJob::TestHelper

  let(:user) { create(:user, locale: "fr") }
  let(:session) { user.sessions.create!(auth_method: "password", user_agent: "Hotwire Native iOS") }
  let(:device) { PushHelpers::Device.generate }
  let!(:subscription) { create_push_subscription(session:, device:) }
  let(:marie) { create(:actor, display_name: "Marie") }
  let(:notification) { create(:notification, user:, actor: marie) }
  let(:posted) { [] }

  around { |example| with_push_env { example.run } }

  def stub_relay(status: 201, body: "")
    stub_request(:post, %r{\Ahttps://push\.allure\.rocks/v1/push/}).to_return do |request|
      posted << request
      { status:, body: }
    end
  end

  def push!(record = notification, target = subscription)
    described_class.perform_now(record.id, target.id)
  end

  def payload(index = 0) = JSON.parse(decrypt_push(posted.fetch(index).body, device))

  it "fans out into one job per subscription of the recipient" do
    other = create_push_subscription(session: user.sessions.create!(auth_method: "password"))
    create_push_subscription(session: create(:user).sessions.create!(auth_method: "password"))

    expect { described_class.perform_now(notification.id) }
      .to have_enqueued_job(described_class).with(notification.id, subscription.id)
      .and have_enqueued_job(described_class).with(notification.id, other.id)
    expect(enqueued_jobs.size).to eq(2)
  end

  it "posts the payload encrypted for the device, signed for the relay" do
    stub_relay
    create(:notification, user:, actor: create(:actor), read_at: nil)
    create(:notification, user:, actor: create(:actor), read_at: Time.current)

    push!

    request = posted.sole
    expect(request.headers).to include("Content-Encoding" => "aes128gcm", "Ttl" => "86400", "Urgency" => "normal")
    expect(request.body).not_to include("Marie")
    scheme, credentials = request.headers["Authorization"].split(" ", 2)
    expect(scheme).to eq("vapid")
    token = credentials[/t=([^,\s]+)/, 1]
    key = credentials[/k=([^,\s]+)/, 1]
    expect(key).to eq(PushHelpers::VAPID[:public_key])
    claims, = JWT.decode(token, WebPush::VapidKey.from_keys(key, PushHelpers::VAPID[:private_key]).curve, true,
                         algorithm: "ES256")
    expect(claims).to include("aud" => "https://push.allure.rocks", "sub" => "mailto:operator@allure.test")
    expect(claims["exp"]).to be_between(Time.current.to_i, 24.hours.from_now.to_i)

    base_url = Allure::Federation.config.base_url
    expect(payload).to eq(
      "v" => 1,
      "origin" => base_url,
      "id" => notification.id.to_s,
      "url" => "#{base_url}/notifications/#{notification.id}",
      "title" => Allure::Federation.config.host,
      "body" => I18n.t("notifications.kinds.follow_request", name: "Marie", locale: :fr),
      "badge" => 2,
      "thread" => "follow_request"
    )
    expect(subscription.reload.last_success_at).to be_present
    expect(metric_value(:push_deliveries_total, result: "delivered")).to eq(1)
  end

  it "writes in the recipient's locale and names the instance when it has a name" do
    stub_relay
    user.update!(locale: "en")

    with_push_env(push_env("INSTANCE_NAME" => "Allure Rocks")) { push! }

    expect(payload["body"]).to eq(I18n.t("notifications.kinds.follow_request", name: "Marie", locale: :en))
    expect(payload["title"]).to eq("Allure Rocks")
  end

  it "sends the generic copy when the device hides the content" do
    stub_relay
    subscription.update!(hide_content: true)

    push!

    expect(payload["body"]).to eq("Vous avez une nouvelle notification")
    expect(payload["thread"]).to eq("allure")
    expect(decrypt_push(posted.sole.body, device)).not_to include("Marie")
  end

  it "renders the inbox sentence through the view helpers, as plain text" do
    stub_relay
    owner_workout = create(:workout, user:, title: "Sortie <b>du</b> dimanche & co")
    comment_author = create(:local_actor, user: create(:user, display_name: "Paul"))
    comment = create(:comment, workout: owner_workout, actor: comment_author)
    record = Notification.create!(user:, kind: "comment", actor: comment_author, subject: comment)

    push!(record)

    expect(payload["body"]).to eq("Paul a commenté votre activité « Sortie <b>du</b> dimanche & co »")
    expect(payload["thread"]).to eq("comment")
  end

  it "keeps the plaintext under 2 KB" do
    stub_relay
    marie.update_columns(display_name: "Marie " * 600)

    push!

    plaintext = decrypt_push(posted.sole.body, device)
    expect(plaintext.bytesize).to be < 2_048
    expect(JSON.parse(plaintext)["body"]).to end_with("…").and start_with("Marie Marie")
  end

  it "pushes nothing for a read or deleted notification, or while push is unconfigured" do
    stub_relay
    notification.mark_read!
    push!

    gone_id = create(:notification, user:).tap(&:destroy!).id
    described_class.perform_now(gone_id, subscription.id)

    fresh = create(:notification, user:)
    with_push_env(push_env("VAPID_PRIVATE_KEY" => nil)) { push!(fresh) }

    expect(posted).to be_empty
  end

  it "never sends one account's notification to another account's subscription" do
    stub_relay
    stranger = create_push_subscription(session: create(:user).sessions.create!(auth_method: "password"))

    push!(notification, stranger)

    expect(posted).to be_empty
  end

  [ 404, 410 ].each do |status|
    it "deletes the subscription when the relay answers #{status}" do
      stub_relay(status:)

      push!

      expect(PushSubscription.exists?(subscription.id)).to be(false)
      expect(metric_value(:push_deliveries_total, result: "gone")).to eq(1)
    end
  end

  it "deletes the subscription when its endpoint is bound to another VAPID key" do
    stub_relay(status: 403, body: '{"error":"key_mismatch"}')

    expect { push! }.not_to have_enqueued_job(described_class)

    expect(PushSubscription.exists?(subscription.id)).to be(false)
    expect(metric_value(:push_deliveries_total, result: "gone")).to eq(1)
  end

  [ '{"error":"forbidden"}', "[]", "not json" ].each do |body|
    it "keeps the subscription on any other 403 (#{body})" do
      stub_relay(status: 403, body:)

      push!

      expect(subscription.reload.failure_count).to eq(1)
      expect(metric_value(:push_deliveries_total, result: "rejected")).to eq(1)
    end
  end

  it "counts a refused push without retrying it" do
    stub_relay(status: 400)

    expect { push! }.not_to have_enqueued_job(described_class)

    expect(subscription.reload.failure_count).to eq(1)
    expect(metric_value(:push_deliveries_total, result: "rejected")).to eq(1)
  end

  it "retries a 503, a 429 and a network failure with back-off, counting each" do
    stub_relay(status: 503)
    expect { push! }.to have_enqueued_job(described_class).with(notification.id, subscription.id)
    expect(subscription.reload.failure_count).to eq(1)

    stub_relay(status: 429)
    expect { push! }.to have_enqueued_job(described_class)

    stub_request(:post, %r{\Ahttps://push\.allure\.rocks/}).to_timeout
    expect { push! }.to have_enqueued_job(described_class)
    expect(subscription.reload.failure_count).to eq(3)
    expect(metric_value(:push_deliveries_total, result: "failed")).to eq(3)
  end

  it "deletes the subscription after ten failures in a row and stops retrying" do
    stub_relay(status: 503)
    subscription.update_columns(failure_count: 9)

    expect { push! }.not_to have_enqueued_job(described_class)

    expect(PushSubscription.exists?(subscription.id)).to be(false)
  end

  it "resets the count on a success" do
    stub_relay
    subscription.update_columns(failure_count: 4)

    push!

    expect(subscription.reload.failure_count).to eq(0)
  end

  it "never posts to an origin that is no longer listed" do
    stub_relay
    with_push_env(push_env("PUSH_RELAY_ORIGINS" => "https://relay.example")) { push! }

    expect(posted).to be_empty
    expect(subscription.reload.failure_count).to eq(1)
  end
end
