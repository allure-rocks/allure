# frozen_string_literal: true

module Admin
  class FundingController < BaseController
    include Pagy::Method

    before_action :require_funding

    def index
      @pagy, @contributions = pagy(FundingContribution.includes(:user, :funding_reversals).latest_first, limit: 25)
      @unmatched_subscriptions = FundingSubscription.unmatched.order(created_at: :desc)
      @accounts = User.where(suspended_at: nil, deletion_scheduled_at: nil).order(:username) if @unmatched_subscriptions.any?
    end

    def create
      account = User.find(params[:account_id])
      ::Funding::ManualGrant.call(user: account, actor: current_user, tier: params.permit(:tier)[:tier])
      redirect_to admin_account_path(account), notice: t("funding.admin.granted")
    rescue ActiveRecord::RecordInvalid
      redirect_to admin_account_path(account), alert: t("funding.admin.invalid")
    end

    def attach
      subscription = FundingSubscription.unmatched.find(params[:id])
      account = User.find(params[:account_id])
      ::Funding::AttachSubscription.call(subscription:, user: account, actor: current_user)
      redirect_to admin_funding_path, notice: t("funding.admin.attached")
    rescue ActiveRecord::RecordInvalid
      redirect_to admin_funding_path, alert: t("funding.admin.attach_invalid")
    end

    def destroy
      contribution = FundingContribution.find(params[:id])
      contribution.with_lock do
        unless contribution.revoked?
          contribution.revoke!
          Audit.record(actor: current_user, action: :funding_revoked, subject: contribution)
        end
      end
      redirect_to admin_funding_path, notice: t("funding.admin.revoked")
    end

    private

    def require_funding
      head :not_found unless Allure::Funding.enabled? && !helpers.hotwire_native_app?
    end
  end
end
