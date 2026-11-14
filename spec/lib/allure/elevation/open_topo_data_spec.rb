# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Elevation::OpenTopoData do
  subject(:client) { described_class.new(base_url: "https://elevation.test", dataset: "mapzen") }

  def stub_elevations(locations:, body:, status: 200)
    stub_request(:get, "https://elevation.test/v1/mapzen")
      .with(query: { "locations" => locations, "interpolation" => "bilinear" })
      .to_return(status:, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  it "requests the configured dataset and returns aligned elevations" do
    stub_elevations(
      locations: "45.064100,6.407200|48.856600,2.352200",
      body: {
        "status" => "OK",
        "results" => [
          { "dataset" => "mapzen", "elevation" => 2636.0 },
          { "dataset" => "mapzen", "elevation" => 46.0 }
        ]
      }
    )

    expect(client.elevations([ [ 45.0641, 6.4072 ], [ 48.8566, 2.3522 ] ])).to eq([ 2636.0, 46.0 ])
  end

  it "keeps a location outside the dataset as nil" do
    stub_elevations(
      locations: "45.064100,6.407200|89.900000,0.000000",
      body: {
        "status" => "OK",
        "results" => [
          { "elevation" => 2636.0 },
          { "elevation" => nil }
        ]
      }
    )

    expect(client.elevations([ [ 45.0641, 6.4072 ], [ 89.9, 0.0 ] ])).to eq([ 2636.0, nil ])
  end

  it "builds the endpoint from a self-hosted base path" do
    client = described_class.new(base_url: "https://elevation.test/opentopodata/", dataset: "srtm30m")

    stub_request(:get, "https://elevation.test/opentopodata/v1/srtm30m")
      .with(query: hash_including("locations" => "45.064100,6.407200"))
      .to_return(status: 200, body: { "status" => "OK", "results" => [ { "elevation" => 2636.0 } ] }.to_json)

    expect(client.elevations([ [ 45.0641, 6.4072 ] ])).to eq([ 2636.0 ])
  end

  it "returns an empty array without a request when there is nothing to look up" do
    expect(client.elevations([])).to eq([])
    expect(WebMock).not_to have_requested(:get, %r{elevation\.test})
  end

  it "refuses more locations than the provider limit" do
    locations = Array.new(described_class::MAX_LOCATIONS + 1) { [ 45.0, 6.0 ] }

    expect { client.elevations(locations) }.to raise_error(ArgumentError, /at most 100 locations/)
    expect(WebMock).not_to have_requested(:get, %r{elevation\.test})
  end

  it "raises a non-retryable error for a rejected request" do
    stub_elevations(
      locations: "45.064100,6.407200",
      status: 400,
      body: { "status" => "INVALID_REQUEST", "error" => "Dataset 'srtm30m' not in config." }
    )

    expect { client.elevations([ [ 45.0641, 6.4072 ] ]) }
      .to raise_error(described_class::InvalidRequestError, /Dataset 'srtm30m' not in config/)
  end

  it "raises a retryable error for provider and transport failures" do
    stub_elevations(
      locations: "45.064100,6.407200",
      status: 500,
      body: { "status" => "SERVER_ERROR", "error" => "Unhandled server error" }
    )
    expect { client.elevations([ [ 45.0641, 6.4072 ] ]) }
      .to raise_error(described_class::UnavailableError, /Unhandled server error/)

    stub_elevations(
      locations: "45.064100,6.407200",
      status: 429,
      body: { "status" => "SERVER_ERROR", "error" => "Too many requests" }
    )
    expect { client.elevations([ [ 45.0641, 6.4072 ] ]) }
      .to raise_error(described_class::UnavailableError, /Too many requests/)

    stub_request(:get, "https://elevation.test/v1/mapzen").to_raise(Net::ReadTimeout)
    expect { client.elevations([ [ 45.0641, 6.4072 ] ]) }
      .to raise_error(described_class::UnavailableError)
  end

  it "raises a retryable error for a malformed response" do
    stub_elevations(
      locations: "45.064100,6.407200",
      body: { "status" => "OK", "results" => [] }
    )
    expect { client.elevations([ [ 45.0641, 6.4072 ] ]) }
      .to raise_error(described_class::UnavailableError, /expected 1 results/)

    stub_elevations(
      locations: "45.064100,6.407200",
      body: { "status" => "OK", "results" => [ { "elevation" => "high" } ] }
    )
    expect { client.elevations([ [ 45.0641, 6.4072 ] ]) }
      .to raise_error(described_class::UnavailableError, /non-numeric elevation/)

    stub_request(:get, "https://elevation.test/v1/mapzen")
      .with(query: hash_including("locations" => "45.064100,6.407200"))
      .to_return(status: 200, body: "not json")
    expect { client.elevations([ [ 45.0641, 6.4072 ] ]) }
      .to raise_error(described_class::UnavailableError, /malformed elevation response/)
  end

  it "refuses a response larger than the size cap" do
    stub_elevations(
      locations: "45.064100,6.407200",
      body: { "status" => "OK", "results" => [ { "elevation" => 2636.0 } ], "padding" => "x" * (300 * 1024) }
    )

    expect { client.elevations([ [ 45.0641, 6.4072 ] ]) }
      .to raise_error(described_class::UnavailableError, /exceeds size limit/)
  end
end
