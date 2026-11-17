# frozen_string_literal: true

module Admin
  # Account administration (docs/dev/ADMIN.md): browse and search accounts,
  # inspect one, and suspend or reinstate it. Suspension revokes access (the
  # sessions are destroyed and sign-in is refused) but never touches content.
  class AccountsController < BaseController
    include Pagy::Method

    STATES = %w[all active suspended].freeze

    def index
      @query = params[:q].to_s.strip
      @state = STATES.include?(params[:state]) ? params[:state] : "all"

      scope = User.order(created_at: :desc, id: :desc)
      if @query.present?
        pattern = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
        scope = scope.where("username ILIKE :pattern OR email_address ILIKE :pattern", pattern:)
      end
      scope = scope.where.not(suspended_at: nil) if @state == "suspended"
      scope = scope.where(suspended_at: nil) if @state == "active"

      @pagy, @accounts = pagy(scope, limit: 25)
      ids = @accounts.map(&:id)
      @workout_counts = Workout.where(user_id: ids).group(:user_id).count
      @publication_counts = WorkoutPublication.active.joins(:workout)
        .where(workouts: { user_id: ids }).group("workouts.user_id").count
    end

    def show
      @account = User.find(params[:id])
      @actor = @account.actor
      @workouts_count = @account.workouts.count
      @publications_count = @account.workout_publications.active.count
      @segments_count = @account.segments.count
      @sessions = @account.sessions.order(created_at: :desc).limit(5)
      @second_factor = Auth::SecondFactorPolicy.new(@account)
      @api_tokens = @account.api_tokens.newest_first.to_a
      @webhooks = @account.webhook_endpoints.newest_first.to_a
      @export = @account.account_exports.newest_first.first
    end

    def photo_quota
      account = User.find(params[:id])
      value = params[:quota_mb].to_s.strip
      megabytes = Integer(value, exception: false)
      unless value.empty? || (megabytes && megabytes >= 0 && megabytes <= (2**63 - 1) / Allure::Photos::Config::MEGABYTE)
        return redirect_to admin_account_path(account), alert: t("photos.admin.invalid")
      end

      account.with_lock do
        account.update!(photo_quota_bytes: value.empty? ? nil : megabytes * Allure::Photos::Config::MEGABYTE)
        Audit.record(actor: current_user, action: :photo_quota_changed, subject: account,
                     metadata: { "quota_bytes" => account.photo_quota_bytes })
      end
      redirect_to admin_account_path(account), notice: t("photos.admin.saved")
    end

    # docs/dev/AUTH.md: removes every factor and session; the account enrols
    # again at its next password sign-in, with no grace period.
    def reset_second_factor
      account = User.find(params[:id])
      if account == current_user
        return redirect_to admin_account_path(account), alert: t("admin.accounts.flash.self_second_factor_reset")
      end

      Auth::FactorChanges.reset!(account)
      audit(:second_factor_reset, account)
      redirect_to admin_account_path(account),
                  notice: t("admin.accounts.flash.second_factor_reset", username: account.username)
    end

    def suspend
      account = User.find(params[:id])
      if account == current_user
        return redirect_to admin_account_path(account), alert: t("admin.accounts.flash.self_suspend")
      end

      account.transaction do
        account.update!(
          suspended_at: Time.current,
          suspension_reason: params.dig(:account, :suspension_reason).presence
        )
        account.sessions.destroy_all
      end
      audit(:account_suspended, account)
      redirect_to admin_account_path(account), notice: t("admin.accounts.flash.suspended", username: account.username)
    end

    def reinstate
      account = User.find(params[:id])
      account.update!(suspended_at: nil, suspension_reason: nil)
      audit(:account_reinstated, account)
      redirect_to admin_account_path(account), notice: t("admin.accounts.flash.reinstated", username: account.username)
    end

    # docs/dev/ACCOUNT.md: the same seven-day window as a member's own
    # request; only the operator may cancel it. The operator account is never
    # deleted from the web.
    def schedule_deletion
      account = User.find(params[:id])
      if account == current_user || account.instance_operator?
        return redirect_to admin_account_path(account), alert: t("admin.accounts.flash.self_deletion")
      end

      Users::DeletionSchedule.new(user: account).schedule!(by: "operator")
      audit(:account_deletion_scheduled, account)
      redirect_to admin_account_path(account),
                  notice: t("admin.accounts.flash.deletion_scheduled", username: account.username)
    rescue Users::DeletionSchedule::NotAllowed
      redirect_to admin_account_path(account)
    end

    def cancel_deletion
      account = User.find(params[:id])
      Users::DeletionSchedule.new(user: account).cancel!
      audit(:account_deletion_cancelled, account)
      redirect_to admin_account_path(account),
                  notice: t("admin.accounts.flash.deletion_cancelled", username: account.username)
    rescue Users::DeletionSchedule::NotAllowed
      redirect_to admin_account_path(account), alert: t("admin.accounts.flash.deletion_started")
    end

    private

    def audit(action, account)
      Audit.record(
        actor: current_user,
        action:,
        subject: account,
        metadata: { "username" => account.username }
      )
    end
  end
end
