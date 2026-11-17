# frozen_string_literal: true

module Admin
  # Registration invitations (docs/dev/ADMIN.md). Only the token digest is
  # stored, so the single-use URL is rendered exactly once on the creation
  # response and can never be recovered; revocation deletes the row.
  class InvitationsController < BaseController
    include Pagy::Method

    MAX_EXPIRY_DAYS = 30
    DEFAULT_EXPIRY_DAYS = 7

    def index
      @pagy, @invitations = pagy(
        RegistrationInvitation.order(created_at: :desc, id: :desc), limit: 25
      )
    end

    def new
      @default_expiry_days = DEFAULT_EXPIRY_DAYS
      @max_expiry_days = MAX_EXPIRY_DAYS
    end

    def create
      email = params.dig(:invitation, :email_address).to_s.strip.downcase
      days = params.dig(:invitation, :expires_in_days).to_i
      days = DEFAULT_EXPIRY_DAYS unless days.positive?
      days = [ days, MAX_EXPIRY_DAYS ].min

      if User.exists?(email_address: email)
        redirect_to admin_new_invitation_path, alert: t("admin.invitations.flash.account_exists")
        return
      end

      @invitation, raw_token = RegistrationInvitation.issue(
        email_address: email, display_name: params.dig(:invitation, :display_name), expires_in: days.days
      )
      @invitation_url = new_registration_url(invitation_token: raw_token)
      audit(:invitation_created, @invitation, email:, display_name: @invitation.display_name)
      render :created, status: :created
    rescue ActiveRecord::RecordInvalid => error
      key = error.record.errors.include?(:display_name) ? "invalid_display_name" : "invalid"
      redirect_to admin_new_invitation_path, alert: t("admin.invitations.flash.#{key}")
    end

    def destroy
      invitation = RegistrationInvitation.find(params[:id])
      audit(:invitation_revoked, invitation, email: invitation.email_address)
      invitation.destroy!
      redirect_to admin_invitations_path, notice: t("admin.invitations.flash.revoked")
    end

    private

    def audit(action, invitation, email:, display_name: nil)
      Audit.record(
        actor: current_user,
        action:,
        subject: invitation,
        metadata: { "email" => email, "display_name" => display_name }.compact
      )
    end
  end
end
