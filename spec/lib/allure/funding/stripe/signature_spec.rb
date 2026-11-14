# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Funding::Stripe::Signature do
  let(:payload) { '{"id":"evt_1"}' }
  let(:secret) { "whsec_test" }
  let(:timestamp) { Time.utc(2026, 10, 27, 12, 0, 0) }

  def signature_header(payload, secret:, at:, timestamp: at.to_i)
    "t=#{timestamp},v1=#{OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{payload}")}"
  end

  it "accepts the signed raw payload within tolerance" do
    header = signature_header(payload, secret:, at: timestamp)
    expect(described_class.verify!(payload, header, secret:, at: timestamp)).to eq(payload)
  end

  it "accepts a secondary signature and rejects forgery, replay and malformed headers" do
    header = signature_header(payload, secret:, at: timestamp)
    rotated = signature_header(payload, secret: "whsec_other", at: timestamp)
    combined = "t=#{timestamp.to_i},v1=#{header.split("v1=").last},v1=#{rotated.split("v1=").last}"
    expect(described_class.verify!(payload, combined, secret:, at: timestamp)).to eq(payload)
    expect(described_class.verify!(payload, combined, secret: "whsec_other", at: timestamp)).to eq(payload)

    tampered = '{"id":"evt_2"}'
    expect { described_class.verify!(tampered, header, secret:, at: timestamp) }.to raise_error(Allure::Funding::Providers::VerificationError)
    expect { described_class.verify!(payload, header, secret: "whsec_other", at: timestamp) }
      .to raise_error(Allure::Funding::Providers::VerificationError)
    expect { described_class.verify!(payload, header, secret:, at: timestamp + 6.minutes) }
      .to raise_error(Allure::Funding::Providers::VerificationError)
    expect { described_class.verify!(payload, "t=#{timestamp.to_i}", secret:, at: timestamp) }
      .to raise_error(Allure::Funding::Providers::VerificationError)
  end
end
