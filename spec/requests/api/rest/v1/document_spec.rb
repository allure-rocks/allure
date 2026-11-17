# frozen_string_literal: true

require "rails_helper"

RSpec.describe "The OpenAPI document (docs/dev/API.md)", type: :request do
  let(:user) { create(:user) }

  it "is members-only" do
    get "/api/rest/v1/openapi.json"

    expect(response).to have_http_status(:unauthorized)
    expect(response.media_type).to eq("application/problem+json")
  end

  it "is served to a signed-in member with this instance's server URL and version" do
    sign_in_as(user)

    get "/api/rest/v1/openapi.json"

    expect(response).to have_http_status(:ok)
    document = response.parsed_body
    expect(document["openapi"]).to eq("3.1.0")
    expect(document["info"]["version"]).to eq(Allure::VERSION)
    expect(document["servers"]).to eq([ { "url" => "#{Allure::Federation.config.base_url}/api/rest/v1",
                                          "description" => Allure::Federation.config.domain } ])
  end

  it "is served as YAML to any valid token, whatever its scopes" do
    get "/api/rest/v1/openapi.yaml", headers: api_headers_for(user, scopes: %w[webhooks])

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/yaml")
    expect(YAML.safe_load(response.body)["paths"]).to have_key("/workouts")
  end

  it "answers 304 while unchanged" do
    headers = api_headers_for(user)
    get "/api/rest/v1/openapi.json", headers: headers

    get "/api/rest/v1/openapi.json", headers: headers.merge("If-None-Match" => response.headers["ETag"])

    expect(response).to have_http_status(:not_modified)
  end
end

RSpec.describe "The OpenAPI document matches the routes (docs/dev/API.md)" do
  let(:document) { YAML.safe_load_file(Rails.root.join("docs/openapi/v1.yaml"), aliases: true) }

  def routed_operations
    Rails.application.routes.routes.filter_map do |route|
      controller = route.defaults[:controller].to_s
      next unless controller.start_with?("api/rest/v1/")
      next if controller.end_with?("/documents", "/fallbacks")

      path = route.path.spec.to_s.delete_suffix("(.:format)").delete_prefix("/api/rest/v1")
      [ route.verb.downcase, path.gsub(/:(\w+)/, '{\1}') ]
    end.uniq
  end

  def documented_operations
    document.fetch("paths").flat_map do |path, item|
      (item.keys & %w[get post put patch delete]).map { [ it, path ] }
    end
  end

  it "documents every route and routes every documented operation" do
    expect(documented_operations).to match_array(routed_operations)
  end

  it "gives every operation an operationId, a scope and a summary" do
    document.fetch("paths").each do |path, item|
      (item.keys & %w[get post put patch delete]).each do |verb|
        operation = item.fetch(verb)
        expect(operation).to include("operationId", "summary", "x-allure-scope"), "#{verb} #{path}"
      end
    end
  end

  it "lists exactly the problem codes the API answers" do
    table = document.fetch("tags").find { it["name"] == "Problems" }.fetch("description")

    expect(table.scan(/^\| `(\w+)` \|/).flatten).to match_array(Api::Rest::V1::Problems::CODES)
  end

  it "declares each scope it names" do
    scopes = document.fetch("paths").values
      .flat_map { |item| item.values.grep(Hash).map { it["x-allure-scope"] } }
      .compact.flat_map { it.split(" or ") }.uniq

    expect(scopes - [ "any" ]).to all(satisfy { ApiToken::SCOPES.include?(it) })
  end
end
