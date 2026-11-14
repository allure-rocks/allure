# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::GarminConnect::DiToken do
  subject(:di) { described_class.new }

  let(:token_url) { "https://diauth.garmin.com/di-oauth2-service/oauth/token" }
  let(:expires) { Time.utc(2026, 10, 9, 12).to_i }

  def jwt(claims, alg: "RS256")
    [ { alg: }, claims ].map { |part| Base64.urlsafe_encode64(part.to_json, padding: false) }.join(".") + ".sig"
  end

  it "falls back through the client ids and reads the JWT claims" do
    stub_request(:post, token_url)
      .with(body: hash_including("client_id" => "GARMIN_CONNECT_MOBILE_ANDROID_DI_2025Q2"))
      .to_return(status: 400, body: "{}")
    stub_request(:post, token_url)
      .with(body: hash_including("client_id" => "GARMIN_CONNECT_MOBILE_ANDROID_DI_2024Q4",
                                 "service_ticket" => "ST-1", "service_url" => "https://connect.garmin.com/app"),
            headers: { "Authorization" => "Basic #{Base64.strict_encode64('GARMIN_CONNECT_MOBILE_ANDROID_DI_2024Q4:')}",
                       "X-Garmin-Client-Platform" => "Android" })
      .to_return(status: 200, body: { access_token: jwt({ exp: expires, client_id: "DI_FROM_JWT" }), refresh_token: "r1" }.to_json)

    token = di.exchange(ticket: "ST-1", service_url: "https://connect.garmin.com/app")

    expect(token.client_id).to eq("DI_FROM_JWT")
    expect(token.refresh_token).to eq("r1")
    expect(token.expires_at).to eq(Time.at(expires))
    expect(token.expires_soon?(now: Time.at(expires - 901))).to be(false)
    expect(token.expires_soon?(now: Time.at(expires - 899))).to be(true)
  end

  it "fails when no client id is accepted" do
    stub_request(:post, token_url).to_return(status: 401, body: "")

    expect { di.exchange(ticket: "ST", service_url: "x") }.to raise_error(Allure::GarminConnect::Error::TokenRejected)
  end

  it "refreshes and keeps the old refresh token when none is rotated" do
    old = described_class::Token.new(access_token: "a", refresh_token: "r1", client_id: "CID", expires_at: nil)
    stub_request(:post, token_url)
      .with(body: { "grant_type" => "refresh_token", "client_id" => "CID", "refresh_token" => "r1" })
      .to_return(status: 200, body: { access_token: jwt({ exp: expires }) }.to_json)

    token = di.refresh(old)

    expect(token).to have_attributes(refresh_token: "r1", client_id: "CID", expires_at: Time.at(expires))
    expect(described_class::Token.from_h(JSON.parse(token.to_h.to_json))).to eq(token)
  end

  it "rejects a refused refresh" do
    stub_request(:post, token_url).to_return(status: 400, body: { error: "invalid_grant" }.to_json)
    old = described_class::Token.new(access_token: "a", refresh_token: "r1", client_id: "CID", expires_at: nil)

    expect { di.refresh(old) }.to raise_error(Allure::GarminConnect::Error::TokenRejected)
  end

  it "ignores the claims of an unsigned token" do
    expect(described_class.claims(jwt({ exp: 1 }, alg: "none"))).to be_nil
    expect(described_class.claims("garbage")).to be_nil
  end
end
