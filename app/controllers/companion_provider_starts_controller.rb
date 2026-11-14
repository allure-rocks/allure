# frozen_string_literal: true

# Where the iOS companion's system browser (ASWebAuthenticationSession) starts
# a provider sign-in (PLAN_AUTH.md §9). OmniAuth only starts on a POST carrying
# this browser's Rails token, so this page posts at once to the request phase,
# with the app's PKCE challenge in the query string that OmniAuth hands back to
# the callback.
class CompanionProviderStartsController < ApplicationController
  allow_unauthenticated_access

  INTENTS = Auth::ProviderSignIn::INTENTS

  def show
    provider = Allure::Auth::Providers.find(params[:provider])
    return head(:not_found) unless provider
    return head(:bad_request) unless params[:code_challenge].to_s.match?(SessionHandoff::CHALLENGE_FORMAT)
    return head(:forbidden) if cross_site?

    # The round trip is this browser's, for this challenge only: the callback
    # hands off only to the attempt started here, and the failure endpoint,
    # which has no OmniAuth parameters, knows to answer the app.
    session[:companion_handoff] = params[:code_challenge]
    query = {
      client: "ios", code_challenge: params[:code_challenge],
      intent: (params[:intent] if INTENTS.include?(params[:intent])),
      invitation_token: params[:invitation_token].presence,
      prompt: ("login" if params[:prompt] == "login"),
      max_age: ("0" if params[:max_age] == "0")
    }.compact
    @action = "/auth/#{provider.name}?#{query.to_query}"
    @provider = provider
    response.headers["Cache-Control"] = "no-store"
    render layout: false
  end

  private
    # The system sign-in sheet opens this page directly (Sec-Fetch-Site:
    # none). Another site may not start a round trip in this browser; a
    # browser that sends no fetch metadata is let through.
    def cross_site?
      site = request.headers["Sec-Fetch-Site"]
      site.present? && %w[none same-origin].exclude?(site)
    end
end
