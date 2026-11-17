# frozen_string_literal: true

require "rails_helper"

# The Prometheus endpoint (docs/dev/METRICS.md): bearer-token access, 404 while
# disabled, and a session-free machine response.
RSpec.describe "Metrics endpoint" do
  around do |example|
    previous = ENV["METRICS_TOKEN"]
    ENV.delete("METRICS_TOKEN")
    example.run
  ensure
    previous.nil? ? ENV.delete("METRICS_TOKEN") : ENV["METRICS_TOKEN"] = previous
  end

  def with_token(token)
    ENV["METRICS_TOKEN"] = token
  end

  it "answers 404 when no token is configured" do
    get "/metrics"

    expect(response).to have_http_status(:not_found)
  end

  it "answers 404 to an authorized request while disabled" do
    get "/metrics", headers: { "Authorization" => "Bearer anything" }

    expect(response).to have_http_status(:not_found)
  end

  it "requires the bearer token when configured" do
    with_token("s3cret")

    get "/metrics"

    expect(response).to have_http_status(:unauthorized)
    expect(response.headers["WWW-Authenticate"]).to eq("Bearer")
  end

  it "rejects a wrong token" do
    with_token("s3cret")

    get "/metrics", headers: { "Authorization" => "Bearer wrong" }

    expect(response).to have_http_status(:unauthorized)
  end

  it "serves the Prometheus exposition to the token holder without a session" do
    with_token("s3cret")

    get "/metrics", headers: { "Authorization" => "Bearer s3cret" }

    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Type"]).to include("text/plain")
    expect(response.headers["Content-Type"]).to include("version=0.0.4")
    expect(response.headers["Cache-Control"]).to eq("no-store")
  end

  it "exposes request metrics and ignores the health check" do
    with_token("s3cret")

    get feed_path
    get "/up"
    get "/metrics", headers: { "Authorization" => "Bearer s3cret" }

    samples = response.body.lines.grep(/^rails_requests_total\{/).join
    expect(samples).to include('controller="feeds"')
    expect(samples).not_to include("rails/health")
    expect(response.body).to include("allure_info{version=\"#{Allure::VERSION}\"} 1")
    expect(response.body).to include("allure_workouts")
    expect(response.body).to include("allure_jobs_database_up 1")
  end

  it "exposes every non-optional catalog family" do
    with_token("s3cret")

    get "/metrics", headers: { "Authorization" => "Bearer s3cret" }

    missing = (Metrics::Catalog.gauges + Metrics::Catalog.histograms)
      .reject { |entry| Metrics::Catalog.optional?(entry.family) }
      .map(&:family)
      .reject { |family| response.body.include?("# TYPE #{family} ") }
    expect(missing).to eq([])
  end

  it "never exposes identifiers or user content" do
    with_token("s3cret")
    user = create(:user, username: "distinctive_rider", display_name: "Distinctive Rider")
    create(:workout, user:, title: "Secret route title", sport: catalog_sport("running"))
    create(:remote_note, actor: create(:actor, uri: "https://leaky.example/users/demo"),
                         source_domain: "leaky.example", status: "active")

    get "/metrics", headers: { "Authorization" => "Bearer s3cret" }

    expect(response.body).not_to include("distinctive_rider", "Distinctive Rider", "Secret route title", "leaky.example")
  end

  it "omits funding entirely after disabling, even after a previous scrape", :funding do
    with_token("s3cret")
    create(:funding_contribution, :beer)
    Metrics::Cache.reset!
    get "/metrics", headers: { "Authorization" => "Bearer s3cret" }
    expect(response.body).to include("# TYPE allure_funding_contributions gauge")
    sample = response.body.lines.find do |line|
      line.start_with?("allure_funding_contributions{") &&
        %w[provider="manual" tier="beer" status="active"].all? { |label| line.include?(label) }
    end
    expect(sample).to match(/\} 1(?:\.0)?\n\z/)
    ENV["FUNDING_ENABLED"] = "false"
    get "/metrics", headers: { "Authorization" => "Bearer s3cret" }
    expect(response.body).not_to include("allure_funding_contributions")
  end
end
