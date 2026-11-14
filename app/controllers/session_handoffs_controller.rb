# frozen_string_literal: true

# The iOS companion's web view collects a provider sign-in made in the system
# browser (PLAN_AUTH.md §9): the app posts the handoff token with its PKCE
# verifier, and the verified answer is resolved here exactly as the browser
# callback would — signing in, account creation, linking, re-authentication,
# or a refusal — in the web view's own session.
class SessionHandoffsController < ApplicationController
  include ProviderSignInResponses

  allow_unauthenticated_access
  rate_limit to: 10, within: 3.minutes,
             with: -> { redirect_to provider_failure_destination, alert: t("provider_callbacks.failed") }

  def create
    payload = SessionHandoff.redeem(token: params[:token].to_s, verifier: params[:verifier].to_s)
    auth = payload && OmniAuth::AuthHash.new(payload["auth"])
    provider = auth && Allure::Auth::Providers.find(auth.provider)
    return redirect_to(provider_failure_destination, alert: t("provider_callbacks.failed")) unless provider

    result = Auth::ProviderSignIn.new(
      auth:, provider:, intent: payload["intent"], current_session: Current.session,
      invitation_token: payload["invitation_token"]
    ).call

    respond_to_provider_result(result, provider)
  end
end
