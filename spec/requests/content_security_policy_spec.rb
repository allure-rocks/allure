# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Content-Security-Policy" do
  def policy = response.headers["Content-Security-Policy"].split(";").to_h { |d| d.strip.split(" ", 2) }

  it "allows only this origin's scripts, with no inline or evaluated code" do
    get new_session_path

    expect(policy).to include("default-src" => "'self'", "object-src" => "'none'", "base-uri" => "'self'",
                              "frame-ancestors" => "'self'")
    expect(policy["script-src"]).to match(/\A'self' 'nonce-[A-Za-z0-9+\/=]+'\z/)
    expect(policy["connect-src"]).to include("https://tiles.openfreemap.org")
  end

  it "runs a self-submitting provider page under its own nonce" do
    post apple_form_post_path, params: { state: "s", code: "c" }

    nonce = policy["script-src"][/'nonce-([^']+)'/, 1]
    expect(response.body).to include(%(<script nonce="#{nonce}">))
  end

  it "lets sign-in forms redirect to the enabled providers" do
    with_providers do
      get new_session_path

      expect(policy["form-action"]).to eq("'self' https://accounts.google.com https://appleid.apple.com https://id.example.test")
    end
  end

  it "lets the funding portal form redirect to the enabled provider's portal", :funding, :stripe_funding do
    get new_session_path

    expect(policy["form-action"]).to eq("'self' https://billing.stripe.com")
  end

  it "keeps the funding portal origin out while the provider is disabled" do
    get new_session_path

    expect(policy["form-action"]).to eq("'self'")
  end
end
