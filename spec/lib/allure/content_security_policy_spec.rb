# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::ContentSecurityPolicy do
  include ProviderHelpers

  def sources(directive, env = {}, development: false) = described_class.sources(directive, env:, development:)

  def with_env(values)
    previous = ENV.to_h.slice(*values.keys)
    values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    values.each_key { |key| previous.key?(key) ? ENV[key] = previous[key] : ENV.delete(key) }
  end

  it "lets the map reach its styles' hosts and the renderer's extra origins" do
    with_env("MAP_STYLE_URL" => "https://tiles.example.org:8443/styles/light.json", "MAP_STYLE_URL_DARK" => nil) do
      expect(sources(:connect, { "ROUTE_IMAGE_MAP_ORIGINS" => "https://fonts.example.org, not a url" }))
        .to eq(%w[https://tiles.example.org:8443 https://fonts.example.org])
    end
  end

  it "adds Vite's hot-reload socket in development only" do
    expect(sources(:connect, development: true)).to include("ws:", "wss:")
    expect(sources(:connect)).not_to include("ws:")
  end

  it "lets sign-in forms redirect to the enabled identity providers only" do
    with_providers do
      expect(sources(:form)).to eq(%w[https://accounts.google.com https://appleid.apple.com https://id.example.test])
    end
    expect(sources(:form)).to eq([])
  end

  it "adds the enabled funding provider's portal origin to form-action" do
    expect(sources(:form)).to eq([])

    with_env(
      "FUNDING_ENABLED" => "true",
      "FUNDING_STRIPE_SECRET_KEY" => "sk_test_csp",
      "FUNDING_STRIPE_WEBHOOK_SECRET" => "whsec_csp",
      "FUNDING_STRIPE_PRICE_COFFEE" => "price_csp",
      "FUNDING_STRIPE_LINK_COFFEE" => "https://buy.stripe.com/test_csp"
    ) do
      expect(sources(:form)).to eq(%w[https://billing.stripe.com])
    end
    expect(sources(:form)).to eq([])
  end

  it "adds the operator's extra origins to every directive, ignoring anything but http(s) origins" do
    env = { "CONTENT_SECURITY_POLICY_SOURCES" => "https://cdn.example.org/path http://Login.Example.org:80 javascript:alert(1) *" }

    described_class::DIRECTIVES.each do |directive|
      expect(sources(directive, env)).to include("https://cdn.example.org", "http://login.example.org")
      expect(sources(directive, env).join(" ")).not_to include("javascript", "*")
    end
  end
end
