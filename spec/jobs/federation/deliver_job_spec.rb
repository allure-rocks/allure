# frozen_string_literal: true

require "rails_helper"

RSpec.describe Federation::DeliverJob do
  it "caps concurrent deliveries at 5 per exact target authority" do
    delivery = build(:federation_delivery, inbox_url: "https://remote.example:8443/inbox")

    expect(described_class.concurrency_limit).to eq(5)
    expect(described_class.new(delivery).concurrency_key).to eq("Federation::DeliverJob/remote.example:8443")
  end
end
