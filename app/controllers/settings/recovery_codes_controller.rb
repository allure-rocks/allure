# frozen_string_literal: true

module Settings
  # Recovery codes (PLAN_AUTH.md §4.3): shown once, right after they are
  # generated, and never again. Regenerating replaces the whole set.
  class RecoveryCodesController < ApplicationController
    before_action :require_recent_authentication, only: :create
    # A visitor on a demo's shared account must not rotate a factor's way in
    # (PLAN_DEMO.md §3).
    before_action :refuse_demo_account_lockout, only: :create

    def show
      @codes = take_fresh_recovery_codes
      return redirect_to settings_security_path if @codes.blank?

      response.headers["Cache-Control"] = "no-store"
    end

    def create
      unless current_user.second_factor_enrolled?
        return redirect_to settings_security_path, alert: t(".not_enrolled"), status: :see_other
      end

      hold_fresh_recovery_codes(Auth::FactorChanges.recovery_codes_regenerated!(current_user))
      redirect_to settings_recovery_codes_path, status: :see_other
    end
  end
end
