# frozen_string_literal: true

# What a resolved provider answer (Auth::ProviderSignIn) does to the browser:
# shared by the provider callback and the iOS companion's handoff exchange,
# which resolves the same answer in the app's web view (PLAN_AUTH.md §9).
module ProviderSignInResponses
  extend ActiveSupport::Concern

  ALERTS = {
    unverified_email: "unverified_email",
    acr_refused: "acr_refused",
    suspended: "suspended",
    email_taken: "email_taken",
    registration_closed: "registration_closed",
    linked_elsewhere: "linked_elsewhere",
    provider_already_linked: "provider_already_linked",
    already_linked: "already_linked",
    mismatch: "mismatch",
    not_reauthenticated: "not_reauthenticated"
  }.freeze

  private
    def respond_to_provider_result(result, provider)
      case result.status
      when :signed_in
        begin_sign_in result.user, auth_method: "provider:#{provider.name}", authenticated_at: result.authenticated_at
      when :onboarding
        session.delete(:pending_sign_in)
        session[:pending_identity] = result.pending
        redirect_to new_onboarding_path
      when :linked
        redirect_to settings_security_path, notice: t("provider_callbacks.linked", provider: provider.label)
      when :reauthenticated
        Current.session.reauthenticate!(result.authenticated_at || Time.current)
        redirect_to(session.delete(:return_to_after_reauthenticating).presence || settings_security_path,
                    notice: t("reauthentications.create.success"))
      when :stale
        session[:return_to_after_reauthenticating] = settings_security_path
        redirect_to new_reauthentication_path, alert: t("provider_callbacks.stale", provider: provider.label)
      else
        redirect_to provider_failure_destination,
                    alert: t("provider_callbacks.#{ALERTS.fetch(result.status)}", provider: provider.label)
      end
    end

    def provider_failure_destination = Current.session ? settings_security_path : new_session_path
end
