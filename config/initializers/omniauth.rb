# frozen_string_literal: true

# Identity providers (PLAN_AUTH.md §6). Only POST starts a provider sign-in,
# and omniauth-rails_csrf_protection checks the Rails authenticity token on it.
# Callback URLs derive from FEDERATION_BASE_URL, never from the request host.
OmniAuth.config.logger = Rails.logger
OmniAuth.config.allowed_request_methods = [ :post ]
OmniAuth.config.full_host = ->(_env) { Allure::Federation.config.base_url }
OmniAuth.config.on_failure = ->(env) { OmniAuth::FailureEndpoint.new(env).redirect_to_failure }

# A callback is bound to the browser's session alone, ID tokens must carry an
# asymmetric signature, and the strategy's logout path is not served
# (PLAN_AUTH.md §6.7). Prepended once the autoloader is up and before the
# middleware stack is built; in development, an edit to the module needs a
# restart, since the strategy keeps the module it was given.
Rails.application.config.after_initialize do
  OmniAuth::Strategies::OpenIDConnect.prepend(Allure::Auth::ProviderStrategyHardening)
end

Rails.application.config.middleware.use OmniAuth::Builder do
  providers = Allure::Auth::Providers
  base_url = Allure::Federation::Config.new.base_url
  # Tests register every strategy and answer through OmniAuth's test mode.
  enabled = Rails.env.test? ? providers::NAMES : providers.enabled.map(&:name)
  placeholder = ->(key) { providers.value(key) || "unset" }

  if enabled.include?("google")
    provider :openid_connect,
             name: :google,
             issuer: providers::GOOGLE_ISSUER,
             discovery: true,
             scope: %i[openid email profile],
             response_type: :code,
             pkce: true,
             # Google signs every ID token with RS256; anything else is forged.
             client_signing_alg: :RS256,
             allow_authorize_params: %i[prompt max_age],
             client_options: {
               identifier: placeholder.("AUTH_GOOGLE_CLIENT_ID"),
               secret: placeholder.("AUTH_GOOGLE_CLIENT_SECRET"),
               redirect_uri: "#{base_url}/auth/google/callback"
             }
  end

  if enabled.include?("apple")
    # Apple answers with a cross-site form POST, which carries no SameSite=Lax
    # cookie. It lands on a Rails page that re-posts it to the OmniAuth
    # callback from this origin, where the session cookie is sent again
    # (AppleFormPostsController).
    provider :apple, placeholder.("AUTH_APPLE_SERVICES_ID"), "",
             scope: "email name",
             team_id: placeholder.("AUTH_APPLE_TEAM_ID"),
             key_id: placeholder.("AUTH_APPLE_KEY_ID"),
             pem: providers.apple_private_key.to_s,
             redirect_uri: "#{base_url}/auth/apple/form_post",
             callback_path: "/auth/apple/return"
  end

  if enabled.include?("oidc")
    provider :openid_connect,
             name: :oidc,
             issuer: placeholder.("AUTH_OIDC_ISSUER"),
             discovery: true,
             scope: %i[openid email profile],
             response_type: :code,
             pkce: true,
             acr_values: providers.oidc_required_acr,
             allow_authorize_params: %i[prompt max_age],
             client_options: {
               identifier: placeholder.("AUTH_OIDC_CLIENT_ID"),
               secret: placeholder.("AUTH_OIDC_CLIENT_SECRET"),
               redirect_uri: "#{base_url}/auth/oidc/callback"
             }

    # The development Dex provider speaks plain HTTP (PLAN_AUTH.md §10);
    # discovery otherwise always builds an https:// URL.
    if !Rails.env.production? && providers.value("AUTH_OIDC_ISSUER").to_s.start_with?("http://")
      SWD.url_builder = URI::HTTP
    end
  end
end
