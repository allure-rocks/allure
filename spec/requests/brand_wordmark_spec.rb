# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Brand wordmark" do
  let(:user) { create(:user) }

  def expect_brand_wordmark(locale:, responsive:)
    body = Nokogiri::HTML(response.body)
    wordmark = body.at_css(".allure-wordmark")

    expect(wordmark).to be_present
    expect(wordmark.text).to eq("allure.")
    expect(wordmark["aria-hidden"]).to eq("true")
    expect(wordmark.at_css(".allure-wordmark-dot").text).to eq(".")
    expect(wordmark["class"].split.include?("allure-wordmark--responsive")).to eq(responsive)
    expect(wordmark.ancestors("a").first["aria-label"]).to eq(I18n.t("app.name", locale:))
    expect(body.at_css("title").text).to end_with(" · Allure")
    expect(wordmark.parent.at_css("svg")).to be_present
  end

  %w[fr en de es nl].each do |locale|
    it "keeps the accessible product name and shared auth wordmark in #{locale}" do
      [ new_session_path, new_registration_path, new_password_path, edit_password_path(user.password_reset_token) ].each do |path|
        get path, params: { locale: }

        expect(response).to have_http_status(:ok)
        expect_brand_wordmark(locale:, responsive: false)
      end
    end

    it "pairs the monogram with the responsive navigation wordmark in #{locale}" do
      sign_in_as(user)

      get workouts_path, params: { locale: }

      expect(response).to have_http_status(:ok)
      expect_brand_wordmark(locale:, responsive: true)
    end
  end

  it "does not add a browser wordmark to the companion's product topbar" do
    sign_in_as(user)

    get workouts_path, headers: { "User-Agent" => "Allure iOS/0.1.0 Hotwire Native iOS; Turbo Native iOS; bridge-components: []" }

    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML(response.body).at_css("header .allure-wordmark")).to be_nil
  end
end
