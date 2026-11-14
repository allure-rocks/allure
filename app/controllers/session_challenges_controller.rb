# frozen_string_literal: true

# The second step of a password sign-in (PLAN_AUTH.md §5.1). No session exists
# until one factor passes: a passkey, an authenticator code, or a recovery
# code. Five wrong answers, five minutes, or a password change end the attempt.
class SessionChallengesController < ApplicationController
  layout "auth"

  allow_unauthenticated_access
  rate_limit to: 10, within: 3.minutes, only: :create,
             with: -> { redirect_to new_session_path, alert: t("sessions.create.rate_limited") }

  before_action :require_pending_user, except: :cancel

  def new
    load_factors(recovery: params[:recovery].present?)
  end

  # Cancel: the pending sign-in ends here rather than lingering in the
  # browser for whoever uses it next (PLAN_AUTH.md §8).
  def cancel
    session.delete(:pending_sign_in)
    session.delete(:webauthn_authentication_challenge)
    redirect_to new_session_path, status: :see_other
  end

  def options
    options = Auth::Passkeys.authentication_options(@user)
    session[:webauthn_authentication_challenge] = options.challenge
    render json: options
  end

  def create
    method = Auth::SecondFactorVerification.call(
      @user, code: params[:recovery_code].presence || params[:code], assertion: params[:assertion],
             challenge: session.delete(:webauthn_authentication_challenge)
    )

    if method
      complete_sign_in @user, second_factor: method, auth_method: pending_sign_in_auth_method
    else
      count_failed_attempt
    end
  end

  private

    def require_pending_user
      @user = pending_sign_in_user
      return if @user

      session.delete(:pending_sign_in)
      respond_to do |format|
        format.json { head :not_found }
        format.any { redirect_to new_session_path, alert: t("session_challenges.expired") }
      end
    end

    # A passkey-only account has no code to type: it is offered the passkey,
    # and the recovery field on request.
    def load_factors(recovery:)
      @totp = @user.totp_enrolled?
      @passkeys = @user.webauthn_credentials.exists?
      @recovery = recovery
    end

    def count_failed_attempt
      session[:pending_sign_in]["attempts"] += 1
      if session[:pending_sign_in]["attempts"] >= Allure::Auth::Config.pending_sign_in_attempts
        session.delete(:pending_sign_in)
        redirect_to new_session_path, alert: t("session_challenges.exhausted")
      else
        load_factors(recovery: params[:recovery_code].present?)
        flash.now[:alert] = t("session_challenges.invalid")
        render :new, status: :unprocessable_content
      end
    end
end
