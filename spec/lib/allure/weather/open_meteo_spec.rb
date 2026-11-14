# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Weather::OpenMeteo do
  subject(:client) do
    described_class.new(forecast_url: "https://forecast.test", archive_url: "https://archive.test", api_key:)
  end

  let(:api_key) { nil }
  let(:locations) do
    [
      Allure::Weather::OpenMeteo::Location.new(latitude: 45.2, longitude: 5.7, elevation: 220),
      Allure::Weather::OpenMeteo::Location.new(latitude: 45.3, longitude: 5.8, elevation: 640)
    ]
  end
  let(:hourly) do
    { "time" => [ 1_778_400_000, 1_778_403_600 ] }.merge(
      described_class::VARIABLES.index_with { [ 1.0, 2.0 ] }
    )
  end

  def stub_endpoint(host, path, body:, status: 200)
    stub_request(:get, %r{\Ahttps://#{host}#{path}\?}).to_return(
      status:, body: body.to_json, headers: { "Content-Type" => "application/json" }
    )
  end

  it "asks one call for ten variables, coarsened positions and their elevations" do
    stub = stub_endpoint("forecast.test", "/v1/forecast", body: [ { "hourly" => hourly }, { "hourly" => hourly } ])

    result = client.hourly(endpoint: :forecast, locations:, start_date: Date.new(2026, 5, 10), end_date: Date.new(2026, 5, 10))

    expect(result.length).to eq(2)
    expect(result.first["temperature_2m"]).to eq([ 1.0, 2.0 ])
    expect(stub.with { |request|
      query = Rack::Utils.parse_query(URI(request.uri).query)
      query["latitude"] == "45.2,45.3" && query["longitude"] == "5.7,5.8" && query["elevation"] == "220,640" &&
        query["hourly"].split(",").length == 10 && query["timeformat"] == "unixtime" && !query.key?("apikey")
    }).to have_been_requested
  end

  it "accepts a single-location object and sends the key when configured" do
    stub = stub_endpoint("archive.test", "/v1/archive", body: { "hourly" => hourly })
    keyed = described_class.new(forecast_url: "https://forecast.test", archive_url: "https://archive.test", api_key: "k")

    result = keyed.hourly(endpoint: :archive, locations: locations.first(1), start_date: Date.new(2010, 1, 1),
                          end_date: Date.new(2010, 1, 1))

    expect(result.first["time"]).to eq(hourly["time"])
    expect(stub.with(query: hash_including("apikey" => "k"))).to have_been_requested
  end

  it "treats 429 and 5xx as retryable and other rejections as final" do
    stub_endpoint("forecast.test", "/v1/forecast", status: 429, body: { "error" => true, "reason" => "Too many" })
    expect {
      client.hourly(endpoint: :forecast, locations:, start_date: Date.current, end_date: Date.current)
    }.to raise_error(described_class::UnavailableError, /Too many/)

    stub_endpoint("forecast.test", "/v1/forecast", status: 400, body: { "error" => true, "reason" => "Bad date" })
    expect {
      client.hourly(endpoint: :forecast, locations:, start_date: Date.current, end_date: Date.current)
    }.to raise_error(described_class::InvalidRequestError, /Bad date/)
  end

  it "refuses more than ten locations and a malformed answer" do
    expect {
      client.hourly(endpoint: :forecast, locations: locations * 6, start_date: Date.current, end_date: Date.current)
    }.to raise_error(ArgumentError)

    stub_endpoint("forecast.test", "/v1/forecast", body: { "hourly" => hourly })
    expect {
      client.hourly(endpoint: :forecast, locations:, start_date: Date.current, end_date: Date.current)
    }.to raise_error(described_class::UnavailableError, /expected 2/)
  end
end
