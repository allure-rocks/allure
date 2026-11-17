# frozen_string_literal: true

# Account creation from a provider identity (docs/dev/AUTH.md). The verified
# identity waits in the encrypted session for 15 minutes; the person confirms
# what becomes permanent — the username is their federation identity — and the
# account is created without a password.
class OnboardingsController < ApplicationController
  layout "auth"

  allow_unauthenticated_access
  rate_limit to: 10, within: 3.minutes, only: :create,
             with: -> { redirect_to new_session_path, alert: t("registrations.create.rate_limited") }

  before_action :load_pending_identity, except: :destroy

  def new
    @user = User.new(username: suggested_username, display_name: @pending["name"], email_address: @pending["email"])
  end

  def create
    @user = User.new(onboarding_params.merge(email_address: @pending["email"], locale: I18n.locale.to_s,
                                             provider_signup: true))
    invitation = RegistrationInvitation.find_by_token(@pending["invitation_token"]) if @pending["invitation_token"]
    return redirect_to(new_session_path, alert: t("provider_callbacks.registration_closed")) unless
      Allure::Registration.open? || invitation&.usable?

    if create_account(invitation)
      session.delete(:pending_identity)
      begin_sign_in @user, auth_method: "provider:#{@pending['provider']}", notice: t("registrations.create.success")
    else
      render :new, status: :unprocessable_content
    end
  end

  # Cancel: the verified identity is discarded, so nobody else using this
  # browser can finish the account with it (docs/dev/AUTH.md).
  def destroy
    session.delete(:pending_identity)
    redirect_to new_session_path, status: :see_other
  end

  private

    def load_pending_identity
      @pending = session[:pending_identity]
      return if @pending.is_a?(Hash) && @pending["expires_at"].to_i > Time.current.to_i

      session.delete(:pending_identity)
      redirect_to new_session_path, alert: t("onboardings.expired")
    end

    def create_account(invitation)
      User.transaction do
        @user.save!(context: :self_registration)
        @user.identities.create!(provider: @pending["provider"], issuer: @pending["issuer"],
                                 subject: @pending["subject"], email: @pending["provider_email"],
                                 email_verified: true, linked_at: Time.current, last_used_at: Time.current)
        invitation&.accept!
      end
      true
    rescue ActiveRecord::RecordInvalid
      false
    # Two concurrent sign-ups can both pass the validations; the indexes are
    # the backstop, reported like a field error instead of a 500.
    rescue ActiveRecord::RecordNotUnique => error
      case error.message
      when /index_users_on_email_address/ then @user.errors.add(:email_address, :taken)
      when /index_identities/ then @user.errors.add(:base, t("onboardings.identity_taken"))
      else @user.errors.add(:username, :taken)
      end
      false
    end

    # A starting point only: sanitized to the username rules and checked by
    # the live availability field like any sign-up.
    def suggested_username
      [ @pending["nickname"], @pending["provider_email"].to_s.split("@").first ].compact.map do |candidate|
        candidate.downcase.gsub(/[^a-z0-9_]/, "_").squeeze("_").delete_prefix("_").delete_suffix("_")[0, 30]
      end.find(&:present?)
    end

    def onboarding_params
      params.require(:user).permit(:username, :display_name)
    end
end
