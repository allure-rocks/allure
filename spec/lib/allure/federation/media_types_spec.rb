# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Federation::MediaTypes do
  it "defines the preferred ActivityPub, WebFinger, and GPX types" do
    expect(described_class::ACTIVITY_PUB).to eq("application/activity+json")
    expect(described_class::WEBFINGER).to eq("application/jrd+json")
    expect(described_class::GPX).to eq("application/xml+gpx")
  end

  it "keeps the protocol alternatives explicit" do
    expect(described_class::ACTIVITY_PUB_ACCEPTED).to include(
      "application/activity+json",
      "application/ld+json",
      'application/ld+json; profile="https://www.w3.org/ns/activitystreams"',
      "application/json"
    )
    expect(described_class::WEBFINGER_ACCEPTED).to eq(
      [ "application/jrd+json", "application/json" ]
    )
    expect(described_class::GPX_ACCEPTED).to eq(
      [ "application/xml+gpx", "application/gpx+xml" ]
    )
  end

  it "registers the preferred protocol types with Rails" do
    expect(Mime::Type.lookup(described_class::ACTIVITY_PUB).symbol).to eq(:activity_json)
    expect(Mime::Type.lookup(described_class::WEBFINGER).symbol).to eq(:webfinger)
    expect(Mime::Type.lookup(described_class::GPX).symbol).to eq(:gpx)
  end
end
