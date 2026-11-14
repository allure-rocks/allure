# frozen_string_literal: true

module Settings
  # The self-service deletion (PLAN_ACCOUNT.md §4). The request needs a recent
  # proof of identity, the username typed again and an acknowledgment; it
  # deactivates the account for DeletionSchedule::GRACE. During the window
  # every page leads here, where the account may cancel, download its last
  # export or sign out.
  class AccountDeletionsController < ApplicationController
    layout "auth", only: :show
    allow_enrolment_only_access only: %i[show destroy]
    allow_deletion_window_access only: %i[show destroy]
    before_action :require_recent_authentication, only: :create
    # A visitor on a demo's shared account must not take the whole instance
    # down with it (PLAN_DEMO.md §3).
    before_action :refuse_demo_account_lockout, only: :create
    before_action :set_no_store

    def show
      return redirect_to settings_account_path unless current_user.deletion_scheduled?

      @user = current_user
      @export = current_user.account_exports.newest_first.first
      @export = nil unless @export&.downloadable?
    end

    def create
      if current_user.instance_operator?
        return redirect_to settings_account_path, alert: t("settings.account.deletion.flash.operator")
      end
      unless confirmed?
        return redirect_to settings_account_path(anchor: "account-deletion"),
                           alert: t("settings.account.deletion.flash.unconfirmed")
      end

      Users::DeletionSchedule.new(user: current_user).schedule!(by: "self", keep_session: Current.session)
      redirect_to settings_account_deletion_path, status: :see_other
    rescue Users::DeletionSchedule::NotAllowed
      redirect_to settings_account_deletion_path, status: :see_other
    end

    # A deletion the operator scheduled is the operator's to cancel
    # (PLAN_ACCOUNT.md §4.4).
    def destroy
      return redirect_to settings_account_deletion_path, status: :see_other if current_user.deletion_requested_by == "operator"

      Users::DeletionSchedule.new(user: current_user).cancel!
      redirect_to settings_account_path, notice: t("settings.account.deletion.flash.cancelled"), status: :see_other
    rescue Users::DeletionSchedule::NotAllowed
      redirect_to settings_account_path, status: :see_other
    end

    private

    def confirmed?
      params.dig(:deletion, :username).to_s.strip.downcase == current_user.username &&
        params.dig(:deletion, :acknowledged) == "1"
    end

    def set_no_store
      response.set_header("Cache-Control", "no-store")
    end
  end
end
