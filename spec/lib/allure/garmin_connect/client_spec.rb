# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::GarminConnect::Client do
  let(:token) { Allure::GarminConnect::DiToken::Token.new(access_token: "a1", refresh_token: "r1", client_id: "CID", expires_at: nil) }
  let(:fresh) { Allure::GarminConnect::DiToken::Token.new(access_token: "a2", refresh_token: "r2", client_id: "CID", expires_at: nil) }
  let(:di_token) { instance_double(Allure::GarminConnect::DiToken, refresh: fresh) }
  let(:pauses) { [] }
  let(:now) { [ 0.0 ] }
  let(:client) do
    described_class.new(token:, di_token:, clock: -> { now.first }, sleeper: ->(seconds) { pauses << seconds })
  end
  let(:profile_url) { "https://connectapi.garmin.com/userprofile-service/socialProfile" }

  it "sends the bearer and the native headers" do
    stub_request(:get, profile_url)
      .with(headers: { "Authorization" => "Bearer a1", "X-App-Ver" => "10861", "User-Agent" => "GCM-Android-5.23" })
      .to_return(status: 200, body: { profileId: 42 }.to_json)

    expect(client.social_profile).to eq("profileId" => 42)
  end

  it "refreshes once after a 401 and keeps the new token" do
    stub_request(:get, profile_url).with(headers: { "Authorization" => "Bearer a1" }).to_return(status: 401)
    stub_request(:get, profile_url).with(headers: { "Authorization" => "Bearer a2" }).to_return(status: 200, body: "{}")

    client.social_profile

    expect(client.token).to eq(fresh)
  end

  it "hands the rotated token to the caller before the retried request" do
    persisted = []
    stub_request(:get, profile_url).with(headers: { "Authorization" => "Bearer a1" }).to_return(status: 401)
    stub_request(:get, profile_url).with(headers: { "Authorization" => "Bearer a2" })
      .to_return { persisted.dup.then { |seen| { status: 200, body: { seen: seen.size }.to_json } } }

    body = described_class.new(token:, di_token:, on_refresh: ->(fresh_token) { persisted << fresh_token }).social_profile

    expect(persisted).to eq([ fresh ])
    expect(body).to eq("seen" => 1)
  end

  it "refreshes before a call when the token expires within 15 minutes" do
    expiring = token.with(expires_at: Time.now + 60)
    stub_request(:get, profile_url).with(headers: { "Authorization" => "Bearer a2" }).to_return(status: 200, body: "{}")

    described_class.new(token: expiring, di_token:).social_profile

    expect(di_token).to have_received(:refresh).with(expiring)
  end

  it "raises TokenRejected when the refreshed token is refused too" do
    stub_request(:get, profile_url).to_return(status: 401)

    expect { client.social_profile }.to raise_error(Allure::GarminConnect::Error::TokenRejected)
  end

  it "spaces requests by one second" do
    stub_request(:get, profile_url).to_return(status: 200, body: "{}")

    client.social_profile
    now[0] = 0.25
    client.social_profile

    expect(pauses).to eq([ 0.75 ])
  end

  it "lists activities with the date window" do
    stub = stub_request(:get, "https://connectapi.garmin.com/activitylist-service/activities/search/activities")
      .with(query: { "start" => "0", "limit" => "50", "startDate" => "2026-10-01", "endDate" => "2026-10-09" })
      .to_return(status: 200, body: [ { activityId: 1 } ].to_json)

    expect(client.activities(start_date: Date.new(2026, 10, 1), end_date: Date.new(2026, 10, 9))).to eq([ { "activityId" => 1 } ])
    expect(stub).to have_been_requested
  end

  it "streams the original ZIP within its cap" do
    url = "https://connectapi.garmin.com/download-service/files/activity/77"
    stub_request(:get, url).to_return(status: 200, body: "PK\x03\x04zip")
    io = StringIO.new(+"", "w+b")

    client.download_original(77, io:)
    expect(io.read).to eq("PK\x03\x04zip".b)

    expect { client.download_original(77, io: StringIO.new(+""), max_bytes: 3) }
      .to raise_error(Allure::GarminConnect::Error::Unavailable, /exceeds/)
  end

  it "maps a missing original to NotFound" do
    stub_request(:get, "https://connectapi.garmin.com/download-service/files/activity/5").to_return(status: 404)

    expect { client.download_original(5, io: StringIO.new(+"")) }.to raise_error(Allure::GarminConnect::Error::NotFound)
  end

  it "refuses a host outside the region" do
    http = Allure::GarminConnect::Http.new(allowed_hosts: Allure::GarminConnect::Region.new.hosts)

    expect { http.get("https://evil.test/") }.to raise_error(ArgumentError)
    expect { http.get("http://sso.garmin.com/") }.to raise_error(ArgumentError)
  end
end
