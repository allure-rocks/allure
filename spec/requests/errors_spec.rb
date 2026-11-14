# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Error pages" do
  it "serves 404 with the themed page" do
    get "/404"

    expect(response).to have_http_status(:not_found)
    expect(response.body).to include("Page introuvable")
  end

  # The one that matters for federation. A deleted actor answers 410 so remote
  # instances purge it; 404 would be read as transient and retried forever.
  it "serves 410 for deleted actors" do
    get "/410"

    expect(response).to have_http_status(:gone)
    expect(response.body).to include("Ce compte a été supprimé")
  end

  # Asserted numerically: Rack renamed this symbol from :unprocessable_entity to
  # :unprocessable_content, so the symbol is version-dependent and the number is not.
  it "serves 422" do
    get "/422"
    expect(response).to have_http_status(422)
  end

  it "serves 500" do
    get "/500"
    expect(response).to have_http_status(:internal_server_error)
  end

  it "answers JSON for API clients rather than returning HTML" do
    get "/410", headers: { "Accept" => "application/json" }

    expect(response).to have_http_status(:gone)
    expect(response.parsed_body).to include("status" => 410)
  end

  it "responds in English when asked" do
    get "/404?locale=en"
    expect(response.body).to include("Page not found")
  end
end
