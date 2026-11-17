# frozen_string_literal: true

module Settings
  # Authenticator-app enrolment (docs/dev/AUTH.md). The secret lives in the
  # encrypted Rails session until a valid code confirms the person's app holds
  # it; only then is it stored on the account.
  class TotpsController < ApplicationController
    allow_enrolment_only_access
    before_action :require_recent_authentication
    # A visitor on a demo's shared account must not enrol a factor the next
    # visitor cannot answer (docs/dev/DEMO.md).
    before_action :refuse_demo_account_lockout, only: %i[create destroy]

    def new
      load_enrolment
    end

    def create
      secret = pending_secret
      step = secret && Auth::Totp.step_for(secret, params[:code])
      unless step
        load_enrolment
        flash.now[:alert] = t(".invalid")
        return render :new, status: :unprocessable_content
      end

      replacing = current_user.totp_enrolled?
      current_user.update!(otp_secret: secret, otp_enrolled_at: Time.current, otp_last_used_step: step)
      session.delete(:pending_otp_secret)
      codes = Auth::FactorChanges.enrolled!(current_user, method: :totp, event: "totp_enrolled", session: Current.session)
      finish(codes, notice: t(replacing ? ".replaced" : ".success"))
    end

    def destroy
      return redirect_to settings_security_path, alert: t("settings.second_factor.last_factor") unless
        Auth::FactorChanges.removable?(current_user)

      current_user.update!(otp_secret: nil, otp_enrolled_at: nil, otp_last_used_step: nil)
      Auth::FactorChanges.removed!(current_user, event: "totp_removed")
      redirect_to settings_security_path, notice: t(".success"), status: :see_other
    end

    private

    def load_enrolment
      @secret = pending_secret || Auth::Totp.generate_secret.tap do |secret|
        session[:pending_otp_secret] = { "user_id" => current_user.id, "secret" => secret }
      end
      @qr_svg = Auth::Totp.qr_svg(Auth::Totp.provisioning_uri(current_user, @secret))
    end

    # The secret being enrolled, bound to its account: another account in the
    # same browser always gets its own (docs/dev/AUTH.md).
    def pending_secret
      pending = session[:pending_otp_secret]
      pending["secret"] if pending.is_a?(Hash) && pending["user_id"] == current_user.id
    end

    def finish(codes, notice:)
      if codes
        hold_fresh_recovery_codes(codes)
        redirect_to settings_recovery_codes_path, notice:
      else
        redirect_to settings_security_path, notice:
      end
    end
  end
end
