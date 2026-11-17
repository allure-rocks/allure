# frozen_string_literal: true

# The return from an identity provider (docs/dev/AUTH.md). OmniAuth has already
# checked the state, the nonce and the ID token; this controller decides what
# the verified identity means for this instance. A round trip the iOS
# companion started in the system browser is handed back to the app instead
# (§9), which resolves it in its own web view.
class ProviderCallbacksController < ApplicationController
  include ProviderSignInResponses

  # The app's callback; ASWebAuthenticationSession captures it before any
  # other app could.
  COMPANION_CALLBACK = "allure://auth/handoff"

  allow_unauthenticated_access
  # OmniAuth verified the round trip's `state`; Apple's answer arrives as a
  # POST re-posted by AppleFormPostsController without a Rails token.
  skip_forgery_protection only: :create

  def create
    auth = request.env["omniauth.auth"]
    provider = auth && Allure::Auth::Providers.find(auth.provider)
    omniauth_params = request.env["omniauth.params"] || {}
    return hand_off_to_companion(auth, provider, omniauth_params) if omniauth_params["client"] == "ios"
    return redirect_to(new_session_path, alert: t("provider_callbacks.failed")) unless provider

    result = Auth::ProviderSignIn.new(
      auth:, provider:, intent: omniauth_params["intent"], current_session: Current.session,
      invitation_token: omniauth_params["invitation_token"]
    ).call

    respond_to_provider_result(result, provider)
  end

  def failure
    if session.delete(:companion_handoff)
      redirect_to "#{COMPANION_CALLBACK}?status=failed", allow_other_host: true
    else
      redirect_to provider_failure_destination, alert: t("provider_callbacks.failed")
    end
  end

  private
    # Nothing is decided in the system browser: the verified answer waits for
    # the app's web view, whose session is the one that signs in or links.
    def hand_off_to_companion(auth, provider, omniauth_params)
      started = session.delete(:companion_handoff)
      challenge = omniauth_params["code_challenge"].to_s
      # Only the attempt this browser started on the start page, with this
      # very challenge; PKCE stays the binding to the app.
      unless provider && challenge.match?(SessionHandoff::CHALLENGE_FORMAT) &&
             started.is_a?(String) && ActiveSupport::SecurityUtils.secure_compare(started, challenge)
        return redirect_to("#{COMPANION_CALLBACK}?status=failed", allow_other_host: true)
      end

      token = SessionHandoff.issue!(
        code_challenge: challenge,
        payload: { "auth" => Auth::ProviderSignIn.portable(auth), "intent" => omniauth_params["intent"],
                   "invitation_token" => omniauth_params["invitation_token"] }.compact
      )
      redirect_to "#{COMPANION_CALLBACK}?#{{ token: }.to_query}", allow_other_host: true
    end
end
