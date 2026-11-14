# frozen_string_literal: true

module Allure
  module Auth
    # Hardening of the openid_connect OmniAuth strategy (PLAN_AUTH.md §6.7),
    # prepended to it at boot by the OmniAuth initializer.
    #
    # The strategy keeps the nonce and the PKCE verifier of a round trip in
    # the session, but reads a `nonce` or `code_verifier` request parameter
    # first when the callback carries one, and lets a request-phase
    # `redirect_uri` parameter rewrite the registered callback URL. No
    # provider ever sends those parameters: a callback carrying one is forged
    # and is refused before any token request, so the session alone binds the
    # answer to the browser that started the round trip.
    #
    # The strategy also verifies an ID token with the client secret when the
    # token's header names an HMAC algorithm. Only asymmetric signatures are
    # accepted here, whatever the provider's metadata offers: a leaked client
    # secret must never become a key that signs identities.
    #
    # Sign-out is local (§6.6): the strategy's RP-initiated logout path
    # (`/auth/:provider/logout`), which Allure never links and which anyone
    # could open, is not served.
    module ProviderStrategyHardening
      FORGED_CALLBACK_PARAMS = %w[nonce code_verifier redirect_uri].freeze
      SHARED_SECRET_ALGORITHMS = %i[HS256 HS384 HS512 none].freeze

      def callback_phase
        forged = FORGED_CALLBACK_PARAMS & params.keys
        return super if forged.empty?

        fail!(:forged_callback, callback_error(:forged_callback, "unexpected callback parameter #{forged.join(', ')}"))
      end

      def other_phase
        call_app!
      end

      private

      def validate_client_algorithm!(algorithm)
        if SHARED_SECRET_ALGORITHMS.include?(algorithm.to_s.to_sym)
          raise callback_error(:invalid_jwt_algorithm,
                               "Received JWT is signed with #{algorithm}; only asymmetric signatures are accepted")
        end

        super
      end

      # The registered callback, whatever the request phase was asked.
      def redirect_uri
        client_options.redirect_uri
      end

      def callback_error(error, reason)
        OmniAuth::Strategies::OpenIDConnect::CallbackError.new(error:, reason:)
      end
    end
  end
end
