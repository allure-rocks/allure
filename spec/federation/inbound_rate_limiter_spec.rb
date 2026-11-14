# frozen_string_literal: true

require "rails_helper"

RSpec.describe Federation::Safety::InboundRateLimiter do
  let(:now) { Time.utc(2026, 8, 26, 12) }
  let(:domain) { "remote.example:8443" }
  let(:recipient) { create(:local_actor) }

  def seed_items(count, created_at:, for_domain: domain)
    rows = Array.new(count) do |index|
      {
        recipient_actor_id: recipient.id,
        activity_uri: "https://#{for_domain}/activities/#{index}-#{SecureRandom.hex(4)}",
        activity_type: "Follow",
        actor_uri: "https://#{for_domain}/users/demo",
        remote_domain: for_domain,
        raw_body_digest: "SHA-256=#{Base64.strict_encode64(Digest::SHA256.digest("#{for_domain}-#{index}"))}",
        raw: { "id" => "https://#{for_domain}/activities/#{index}", "type" => "Follow" },
        status: "pending",
        attempts: 0,
        created_at:,
        updated_at: created_at
      }
    end
    FederationInboxItem.insert_all(rows)
  end

  it "allows an authority below both limits" do
    seed_items(59, created_at: now)

    expect(described_class.check(domain, now:)).to be_allowed
  end

  it "denies the 61st activity of the minute" do
    seed_items(60, created_at: now)

    result = described_class.check(domain, now:)

    expect(result).not_to be_allowed
    expect(result.retry_after).to be_between(1, 60)
  end

  it "denies an authority past the hourly limit even when the minute is clear" do
    seed_items(600, created_at: now - 5.minutes)

    result = described_class.check(domain, now:)

    expect(result).not_to be_allowed
    expect(result.retry_after).to be > 60
  end

  it "ignores activity older than the window" do
    seed_items(600, created_at: now - 2.hours)

    expect(described_class.check(domain, now:)).to be_allowed
  end

  it "keys on the exact authority, including the port" do
    seed_items(60, created_at: now, for_domain: "remote.example:8443")

    expect(described_class.check("remote.example", now:)).to be_allowed
  end

  it "allows a blank authority" do
    expect(described_class.check(nil, now:)).to be_allowed
  end
end
