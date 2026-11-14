# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Webhook emission and delivery (PLAN_API.md §11)" do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }
  let(:url) { "https://hooks.example.com/allure" }
  let!(:endpoint) { user.webhook_endpoints.create!(url:, events: %w[workout.created publication.activated]) }

  def emit(type = "workout.created", key: "k-#{SecureRandom.hex(4)}")
    Webhooks::Emit.call(user:, type:, dedupe_key: key) { { "workout" => { "id" => "abc" } } }
  end

  describe Webhooks::Signature do
    it "signs as the Standard Webhooks reference does" do
      header = described_class.header([ "whsec_MfKQ9r8GKYqrTwjUPD8ILPZIo2LaLaSw" ], "msg_p5jXN8AQM9LWM0D4loKWxJek",
                                      "1614265330", '{"test": 2432232314}')

      expect(header).to eq("v1,g0hM9SsE+OTPJTGt/tmIKtSyZlE3uFJELVlNIOLJ1OE=")
    end
  end

  describe Webhooks::Emit do
    it "writes one event and one delivery per subscribed endpoint, once per dedupe key" do
      other = user.webhook_endpoints.create!(url: "https://other.example.com/", events: %w[workout.deleted])

      expect { 2.times { emit(key: "same") } }.to change(WebhookEvent, :count).by(1)

      event = WebhookEvent.sole
      expect(event.deliveries.map(&:webhook_endpoint)).to eq([ endpoint ])
      expect(other.deliveries).to be_empty
      expect(Webhooks::DeliverJob).to have_been_enqueued.once
    end

    it "writes nothing for an account without a deliverable subscribed endpoint, or suspended" do
      endpoint.update!(active: false)
      emit
      endpoint.update!(active: true)
      user.update_columns(suspended_at: Time.current)
      emit

      expect(WebhookEvent.count).to eq(0)
    end

    it "waits for the commit and writes nothing for a rolled-back fact" do
      ActiveRecord::Base.transaction(requires_new: true) do
        emit
        expect(WebhookEvent.count).to eq(0)
        raise ActiveRecord::Rollback
      end

      expect(WebhookEvent.count).to eq(0)
    end
  end

  describe Webhooks::DeliverJob do
    def deliver_once
      emit
      delivery = WebhookDelivery.order(:id).last
      described_class.perform_now(delivery)
      delivery.reload
    end

    it "posts the signed envelope and records the success" do
      stub = stub_request(:post, url).to_return(status: 204)

      delivery = deliver_once

      expect(delivery).to have_attributes(status: "succeeded", attempts: 1, last_status_code: 204)
      event = delivery.webhook_event
      expect(stub.with { |request|
        body = JSON.parse(request.body)
        headers = request.headers
        body["id"] == event.public_id && body["type"] == "workout.created" && body["api_version"] == "v1" &&
          headers["Webhook-Id"] == event.public_id && headers["User-Agent"].start_with?("Allure-Webhooks/") &&
          Webhooks::Signature.verify?(endpoint.secret, event.public_id, headers["Webhook-Timestamp"], request.body,
                                      headers["Webhook-Signature"])
      }).to have_been_requested
    end

    it "signs with both secrets during a rotation, and only the new one after it" do
      old_secret = endpoint.secret
      endpoint.rotate_secret!
      signatures = []
      stub_request(:post, url).to_return { |request| signatures << request.headers["Webhook-Signature"]; { status: 200 } }

      deliver_once
      travel 25.hours do
        deliver_once
      end

      expect(signatures.first.split.size).to eq(2)
      event = WebhookEvent.order(:id).first
      expect(signatures.last.split.size).to eq(1)
      expect(Webhooks::Signature.verify?(old_secret, event.public_id, "1", "x", signatures.first)).to be(false)
    end

    it "retries a failure with the next delay, then abandons after the last one" do
      stub_request(:post, url).to_return(status: 500)
      emit
      delivery = WebhookDelivery.sole
      now = Time.current

      WebhookDelivery::RETRY_DELAYS.each do |delay|
        described_class.perform_now(delivery, now:)
        expect(delivery.reload.next_attempt_at).to be_within(1.second).of(now + delay)
        now += delay
      end
      described_class.perform_now(delivery, now:)

      expect(delivery.reload).to have_attributes(status: "abandoned", attempts: 7, last_error: "http_status")
    end

    it "does not attempt a delivery another job holds, nor one not yet due" do
      stub = stub_request(:post, url).to_return(status: 500)
      emit
      delivery = WebhookDelivery.sole
      delivery.update_columns(next_attempt_at: 1.minute.from_now)

      described_class.perform_now(delivery)

      expect(stub).not_to have_been_requested
    end

    it "never follows a redirect" do
      stub_request(:post, url).to_return(status: 302, headers: { "Location" => "https://elsewhere.example.com/" })

      delivery = deliver_once

      expect(delivery).to have_attributes(status: "pending", last_error: "redirect")
      expect(a_request(:post, "https://elsewhere.example.com/")).not_to have_been_made
    end

    it "disables the endpoint on 410 Gone and gives up what was waiting" do
      stub_request(:post, url).to_return(status: 410)
      emit
      waiting = WebhookDelivery.sole
      waiting.update_columns(next_attempt_at: 1.hour.from_now)

      delivery = deliver_once

      expect(delivery.status).to eq("failed")
      expect(endpoint.reload).to have_attributes(state: "disabled_gone")
      expect(waiting.reload.status).to eq("abandoned")
    end

    it "disables an endpoint failing for three days and twenty attempts in a row" do
      stub_request(:post, url).to_return(status: 503)
      endpoint.update_columns(consecutive_failures: 19, first_failure_at: 4.days.ago)

      deliver_once

      expect(endpoint.reload).to have_attributes(disabled_reason: "failing")
    end

    it "refuses an address that resolves to a private network at the attempt" do
      emit
      delivery = WebhookDelivery.sole
      resolve_webhook_hosts_to("10.0.0.5")

      described_class.perform_now(delivery)

      expect(delivery.reload.last_error).to eq("unsafe_url")
      expect(a_request(:post, url)).not_to have_been_made
    end

    it "waits while the endpoint is paused" do
      emit
      delivery = WebhookDelivery.sole
      endpoint.update!(active: false)

      described_class.perform_now(delivery)

      expect(delivery.reload).to have_attributes(status: "pending", attempts: 0)
    end
  end

  describe WebhookEndpoint do
    it "refuses a URL to a private address, plain HTTP, and more than ten endpoints" do
      resolve_webhook_hosts_to("127.0.0.1")
      expect(user.webhook_endpoints.new(url: "https://internal.example.com/", events: %w[workout.created])).not_to be_valid

      resolve_webhook_hosts_to(WebhookHelpers::PUBLIC_ADDRESS)
      # Plain HTTP is the local ring's escape hatch only.
      allow(Allure::Federation.config).to receive(:allow_private_ips?).and_return(false)
      expect(user.webhook_endpoints.new(url: "http://hooks.example.com/", events: %w[workout.created])).not_to be_valid

      9.times { |index| user.webhook_endpoints.create!(url: "https://h#{index}.example.com/", events: [ "*" ]) }
      extra = user.webhook_endpoints.new(url: "https://extra.example.com/", events: [ "*" ])
      expect(extra).not_to be_valid
      expect(extra.errors[:base]).to be_present
    end

    it "keeps the secret encrypted at rest" do
      raw = WebhookEndpoint.connection.select_value("SELECT secret FROM webhook_endpoints WHERE id = #{endpoint.id}")

      expect(raw).not_to include(endpoint.secret)
      expect(endpoint.secret).to start_with("whsec_")
    end
  end

  it "prunes events and deliveries older than 30 days" do
    emit
    WebhookEvent.update_all(created_at: 31.days.ago)

    Webhooks::RecoveryJob.perform_now

    expect(WebhookEvent.count).to eq(0)
    expect(WebhookDelivery.count).to eq(0)
  end
end
