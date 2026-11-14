# frozen_string_literal: true

module Settings
  # Unlinking a provider identity (PLAN_AUTH.md §6.5). Linking happens through
  # the provider round trip itself (ProviderCallbacksController).
  class IdentitiesController < ApplicationController
    before_action :require_recent_authentication
    # A visitor on a demo's shared account must not change how it signs in
    # (PLAN_DEMO.md §3).
    before_action :refuse_demo_account_lockout, only: :destroy

    def destroy
      identity = current_user.identities.find(params[:id])
      unless current_user.password? || current_user.identities.count > 1
        return redirect_to settings_security_path, alert: t(".last_method"), status: :see_other
      end

      identity.destroy!
      SecurityMailer.notice(current_user, "identity_unlinked", provider: identity.label).deliver_later
      redirect_to settings_security_path, notice: t(".success", provider: identity.label), status: :see_other
    end
  end
end
