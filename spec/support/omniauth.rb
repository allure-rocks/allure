# frozen_string_literal: true

# Identity providers answer through OmniAuth's test mode (docs/dev/AUTH.md):
# no discovery, token or JWKS request leaves the test process.
OmniAuth.config.test_mode = true

module ProviderHelpers
  PROVIDER_ENV = {
    "AUTH_GOOGLE_CLIENT_ID" => "google-client", "AUTH_GOOGLE_CLIENT_SECRET" => "google-secret",
    "AUTH_APPLE_SERVICES_ID" => "app.allure.web", "AUTH_APPLE_TEAM_ID" => "ABCDE12345",
    "AUTH_APPLE_KEY_ID" => "KEY123", "AUTH_APPLE_PRIVATE_KEY" => "pem",
    "AUTH_OIDC_ISSUER" => "https://id.example.test", "AUTH_OIDC_CLIENT_ID" => "allure",
    "AUTH_OIDC_CLIENT_SECRET" => "secret", "AUTH_OIDC_LABEL" => "Example ID"
  }.freeze

  def with_providers(env = PROVIDER_ENV)
    previous = ENV.to_h.slice(*env.keys)
    env.each { |key, value| ENV[key] = value }
    yield
  ensure
    env.each_key { |key| previous.key?(key) ? ENV[key] = previous[key] : ENV.delete(key) }
  end

  def mock_provider(provider = :google, uid: "subject-1", email: "rider@example.test", verified: true,
                    name: "Rider Example", nickname: nil, acr: nil, amr: nil, auth_time: nil)
    # raw_info stands for the strategy's verified claims: `acr`, `amr` and
    # `auth_time` (an epoch, as the ID token carries it) included.
    OmniAuth.config.mock_auth[provider] = OmniAuth::AuthHash.new(
      provider: provider.to_s, uid:,
      info: { email:, name:, nickname: },
      credentials: { id_token: "header.payload.signature" },
      extra: { raw_info: { "email_verified" => verified, "acr" => acr, "amr" => amr,
                           "auth_time" => auth_time&.to_i }.compact }
    )
  end

  # The OmniAuth round trip in test mode: the POST request phase redirects to
  # the callback, which answers with the mocked identity.
  def sign_in_with(provider = :google, **params)
    post "/auth/#{provider}#{"?#{params.to_query}" if params.any?}"
    # The callback URL is absolute on FEDERATION_BASE_URL; stay on the test
    # host so the session cookie follows.
    get URI(response.location).request_uri
  end
end

RSpec.configure do |config|
  config.include ProviderHelpers, type: :request
  config.after { OmniAuth.config.mock_auth.except!(:google, :apple, :oidc) }
end
