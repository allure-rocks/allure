# frozen_string_literal: true

# Re-authentication before a sensitive action (docs/dev/AUTH.md) and the
# operator's second-factor step-up (§5.4). A signed-in person proves their
# identity again — the password, and a second factor once one is enrolled —
# and the current session remembers it for the window.
class ReauthenticationsController < ApplicationController
  layout "auth"

  allow_enrolment_only_access
  rate_limit to: 10, within: 3.minutes, only: :create,
             with: -> { redirect_to new_reauthentication_path, alert: t("reauthentications.create.rate_limited") }

  before_action :load_factors

  def new
  end

  def options
    options = Auth::Passkeys.authentication_options(current_user)
    session[:webauthn_reauthentication_challenge] = options.challenge
    render json: options
  end

  def create
    challenge = session.delete(:webauthn_reauthentication_challenge)
    # A password-less account proves itself with its factor, or through a
    # provider round trip (ProviderCallbacksController) when it has none.
    password = current_user.password? ? current_user.authenticate(params[:password].to_s) : @enrolled
    method = if password && @enrolled
      Auth::SecondFactorVerification.call(current_user, code: params[:recovery_code].presence || params[:code],
                                                        assertion: params[:assertion], challenge:)
    end

    if password && (method || !@enrolled)
      Current.session.reauthenticate!(second_factor: method)
      redirect_to return_path(delete: true), notice: t(".success"), status: :see_other
    else
      flash.now[:alert] = t(@enrolled ? ".invalid_with_factor" : ".invalid")
      render :new, status: :unprocessable_content
    end
  end

  private

    def load_factors
      @enrolled = current_user.second_factor_enrolled?
      @totp = current_user.totp_enrolled?
      @passkeys = current_user.webauthn_credentials.exists?
      @recovery = params[:recovery].present? || params[:recovery_code].present?
      @copy = if current_user.password?
        @enrolled ? "copy_with_factor" : "copy"
      else
        @enrolled ? "copy_factor_only" : "copy_provider"
      end
      linked = current_user.identities.pluck(:provider)
      @reauth_providers = Allure::Auth::Providers.enabled.select { |provider| linked.include?(provider.name) }
    end

    def return_path(delete: false)
      stored = delete ? session.delete(:return_to_after_reauthenticating) : session[:return_to_after_reauthenticating]
      stored.presence || settings_security_path
    end
    helper_method :return_path
end
