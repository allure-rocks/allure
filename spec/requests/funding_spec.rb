# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Instance funding", :funding do
  let(:user) { create(:user) }
  let(:native_headers) { { "User-Agent" => "Allure iOS Hotwire Native" } }

  it "requires sign-in" do
    get funding_path
    expect(response).to redirect_to(new_session_path)
  end

  it "shows hosted checkout links, without inventing a local amount" do
    sign_in_as(user)
    get funding_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("https://payments.example/coffee")
    expect(Nokogiri::HTML(response.body).text).to include(I18n.t("funding.manual_confirmation"))
  end

  it "hides pages and settings when disabled, retaining preferences" do
    sign_in_as(user)
    ENV["FUNDING_ENABLED"] = "false"
    get funding_path
    expect(response).to have_http_status(:not_found)
    get settings_profile_path
    expect(response.body).not_to include('id="user_funding_badge_color"')
    patch settings_profile_path, params: { user: { funding_badge_color: "teal", funding_badge_hidden: "1" } }
    expect(user.reload.funding_badge_color).to eq("primary")
    expect(user).not_to be_funding_badge_hidden
  end

  it "never exposes payment pages or preferences in the companion" do
    sign_in_as(user)
    get funding_path, headers: native_headers
    expect(response).to have_http_status(:not_found)
    get settings_profile_path, headers: native_headers
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('href="/funding"', 'id="user_funding_badge_color"')
    patch settings_profile_path, headers: native_headers, params: { user: { funding_badge_color: "teal" } }
    expect(user.reload.funding_badge_color).to eq("primary")
  end

  it "saves badge preferences on the web and rejects arbitrary colours" do
    sign_in_as(user)
    patch settings_profile_path, params: { user: { funding_badge_color: "teal", funding_badge_hidden: "1" } }
    expect(response).to redirect_to(settings_profile_path)
    expect(user.reload.funding_badge_color).to eq("teal")
    expect(user).to be_funding_badge_hidden
    patch settings_profile_path, params: { user: { funding_badge_color: "#ffffff" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(user.reload.funding_badge_color).to eq("teal")
  end

  describe "automated subscriptions", :stripe_funding do
    it "offers the hosted annual checkout with a signed reference" do
      sign_in_as(user)
      get funding_path
      expect(response).to have_http_status(:ok)
      link = Nokogiri::HTML(response.body).at_css("a[href*='client_reference_id=']")
      expect(link).to be_present
      expect(link["href"]).to start_with(StripeFundingHelpers::STRIPE_TEST_LINK)
      get funding_thanks_path
      expect(response).to have_http_status(:ok)
    end

    it "opens the provider's hosted portal only for the account's own live subscription" do
      sign_in_as(user)
      other = create(:funding_subscription, tier: "coffee")
      owned = create(:funding_subscription, user:, provider: "stripe", external_id: "sub_123",
                     customer_id: "cus_123", tier: "coffee")
      stub_stripe("/v1/subscriptions/sub_123", response: stripe_subscription)
      stub_stripe("/v1/billing_portal/sessions", method: :post,
                  response: { "url" => "https://billing.stripe.com/p/session/abc" })

      post funding_portal_path(other)
      expect(response).to have_http_status(:not_found)

      post funding_portal_path(owned)
      expect(response).to have_http_status(:found)
      expect(response.headers["Location"]).to eq("https://billing.stripe.com/p/session/abc")
    end

    it "keeps the portal form outside Turbo, which cannot follow an external redirect" do
      sign_in_as(user)
      create(:funding_subscription, user:, provider: "stripe", external_id: "sub_123",
             customer_id: "cus_123", tier: "coffee")
      get funding_path
      form = Nokogiri::HTML(response.body).at_css("form[action*='/funding/portal/']")
      expect(form).to be_present
      expect(form["data-turbo"]).to eq("false")
    end

    it "hides the management card and portal from a canceled subscription" do
      sign_in_as(user)
      canceled = create(:funding_subscription, user:, provider: "stripe", external_id: "sub_123",
                        customer_id: "cus_123", tier: "coffee", status: "canceled")
      get funding_path
      expect(response.body).not_to include("/funding/portal/")
      post funding_portal_path(canceled)
      expect(response).to have_http_status(:not_found)
    end
  end
end
