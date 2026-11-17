# frozen_string_literal: true

module Settings
  # Passkey and security-key registration (docs/dev/AUTH.md). The browser asks
  # for creation options, the person's device creates the credential, and the
  # signed answer is verified against the single-use challenge.
  class PasskeysController < ApplicationController
    allow_enrolment_only_access
    before_action :require_recent_authentication
    # A visitor on a demo's shared account must not enrol a factor the next
    # visitor cannot answer (docs/dev/DEMO.md).
    before_action :refuse_demo_account_lockout, only: %i[create destroy]

    def options
      options = Auth::Passkeys.registration_options(current_user)
      session[:webauthn_registration_challenge] = options.challenge
      render json: options
    end

    def create
      credential = Auth::Passkeys.register(
        current_user, params[:credential],
        challenge: session.delete(:webauthn_registration_challenge),
        nickname: params[:nickname].to_s.squish.presence || t(".default_nickname")
      )
      return redirect_to settings_security_path, alert: t(".invalid") unless credential

      codes = Auth::FactorChanges.enrolled!(current_user, method: :webauthn, event: "passkey_added",
                                                          session: Current.session)
      if codes
        hold_fresh_recovery_codes(codes)
        redirect_to settings_recovery_codes_path, notice: t(".success")
      else
        redirect_to settings_security_path, notice: t(".success")
      end
    end

    def destroy
      credential = current_user.webauthn_credentials.find(params[:id])
      return redirect_to settings_security_path, alert: t("settings.second_factor.last_factor") unless
        Auth::FactorChanges.removable?(current_user)

      credential.destroy!
      Auth::FactorChanges.removed!(current_user, event: "passkey_removed")
      redirect_to settings_security_path, notice: t(".success"), status: :see_other
    end
  end
end
