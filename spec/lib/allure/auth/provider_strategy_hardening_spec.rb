# frozen_string_literal: true

require "rails_helper"

# PLAN_AUTH.md §6.7: the real openid_connect strategy, test mode off, against
# a Rack environment. No discovery, token or JWKS request is ever made: every
# refusal happens before the strategy reaches the network.
RSpec.describe Allure::Auth::ProviderStrategyHardening do
  around do |example|
    previous = OmniAuth.config.test_mode
    OmniAuth.config.test_mode = false
    example.run
  ensure
    OmniAuth.config.test_mode = previous
  end

  let(:app) { ->(_env) { [ 404, { "content-type" => "text/plain" }, [ "app" ] ] } }
  let(:strategy) do
    OmniAuth::Strategies::OpenIDConnect.new(
      app, name: :oidc, issuer: "https://id.example.test", discovery: true, pkce: true,
      client_options: { identifier: "allure", secret: "secret", redirect_uri: "http://allure.test:3001/auth/oidc/callback" }
    )
  end

  def env_for(path, session: {})
    Rack::MockRequest.env_for(path, "rack.session" => session)
  end

  def failure_of(response)
    expect(response[0]).to eq(302)
    Rack::Utils.parse_query(URI(response[1]["Location"]).query)
  end

  it "is prepended to the strategy" do
    expect(OmniAuth::Strategies::OpenIDConnect.ancestors.index(described_class))
      .to be < OmniAuth::Strategies::OpenIDConnect.ancestors.index(OmniAuth::Strategies::OpenIDConnect)
  end

  describe "a forged callback" do
    %w[nonce code_verifier redirect_uri].each do |parameter|
      it "refuses a callback carrying #{parameter} before anything else" do
        session = { "omniauth.state" => "state-1", "omniauth.nonce" => "nonce-1", "omniauth.pkce.verifier" => "v" }
        expect(OpenIDConnect::Discovery::Provider::Config).not_to receive(:discover!)

        response = strategy.call(env_for("/auth/oidc/callback?code=c&state=state-1&#{parameter}=x", session:))

        expect(failure_of(response)).to include("message" => "forged_callback", "strategy" => "oidc")
      end
    end

    it "still checks the state of an ordinary callback" do
      response = strategy.call(env_for("/auth/oidc/callback?code=c&state=unknown", session: { "omniauth.state" => "s" }))

      expect(failure_of(response)).to include("message" => "csrf_detected")
    end
  end

  describe "the signature algorithm" do
    %w[HS256 HS384 HS512 none].each do |algorithm|
      it "refuses #{algorithm}" do
        expect { strategy.send(:validate_client_algorithm!, algorithm.to_sym) }
          .to raise_error(OmniAuth::Strategies::OpenIDConnect::CallbackError) { |error|
            expect(error.error).to eq(:invalid_jwt_algorithm)
          }
      end
    end

    it "accepts an asymmetric algorithm" do
      expect { strategy.send(:validate_client_algorithm!, :RS256) }.not_to raise_error
      expect { strategy.send(:validate_client_algorithm!, :ES256) }.not_to raise_error
    end
  end

  it "always sends the registered callback URL" do
    expect(strategy.send(:redirect_uri)).to eq("http://allure.test:3001/auth/oidc/callback")
  end

  it "does not serve the logout path" do
    expect(OpenIDConnect::Discovery::Provider::Config).not_to receive(:discover!)

    response = strategy.call(env_for("/auth/oidc/logout"))

    expect(response[0]).to eq(404)
  end
end
