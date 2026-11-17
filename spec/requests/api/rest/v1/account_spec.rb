# frozen_string_literal: true

require "rails_helper"

RSpec.describe "REST API account and catalog (docs/dev/API.md–6.2)", type: :request do
  let(:user) { create(:user, username: "marion", display_name: "Marion") }

  it "describes the account and the token" do
    get "/api/rest/v1/me", headers: api_headers_for(user, scopes: %w[webhooks])

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include("username" => "marion", "display_name" => "Marion",
                                            "handle" => user.handle)
    expect(response.parsed_body["token"]).to include("name" => "Spec client", "scopes" => %w[webhooks])
    expect(response.parsed_body.to_s).not_to include(user.email_address)
    expect_api_contract
  end

  it "lists the sport catalog with labels in every locale and answers 304 while unchanged" do
    rowing = catalog_sport("rowing")
    headers = api_headers_for(user)

    get "/api/rest/v1/sports", headers: headers

    expect(response).to have_http_status(:ok)
    entry = response.parsed_body["data"].find { it["slug"] == "rowing" }
    expect(entry).to include("pace_basis_metres" => 500, "labels" => User::LOCALES.to_h { [ it, I18n.t("sports.rowing", locale: it) ] })
    expect(rowing).to be_present
    expect_api_contract

    get "/api/rest/v1/sports", headers: headers.merge("If-None-Match" => response.headers["ETag"])
    expect(response).to have_http_status(:not_modified)
  end

  describe "equipment" do
    it "lists only the account's own equipment" do
      mine = create(:equipment, user:, label: "Gravel bike")
      create(:equipment, label: "Someone else's")

      get "/api/rest/v1/equipment", headers: api_headers_for(user)

      expect(response.parsed_body["data"].pluck("id")).to eq([ mine.to_param ])
      expect_api_contract
    end

    it "answers 404 for another account's equipment" do
      other = create(:equipment)
      headers = api_headers_for(user)

      get "/api/rest/v1/equipment/#{other.to_param}", headers: headers
      expect(response).to have_http_status(:not_found)
      expect_api_contract

      mine = create(:equipment, user:)
      get "/api/rest/v1/equipment/#{mine.to_param}", headers: headers
      expect(response.parsed_body).to include("id" => mine.to_param, "label" => mine.label, "active" => true)
      expect_api_contract
    end
  end

  it "lists the publishing profiles by their opaque identifier" do
    PublishingProfile.ensure_built_ins_for!(user)

    get "/api/rest/v1/publishing_profiles", headers: api_headers_for(user)

    profiles = response.parsed_body["data"]
    expect(profiles.pluck("audience")).to include("public")
    expect(profiles.pluck("id")).to all(match(/\A[2-9A-HJ-NP-Za-km-z]{22}\z/))
    expect_api_contract
  end
end
