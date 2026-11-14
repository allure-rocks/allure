class PasswordsController < ApplicationController
  layout "auth"

  allow_unauthenticated_access
  before_action :set_user_by_token, only: %i[ edit update ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_password_path, alert: t("passwords.create.rate_limited") }

  def new
  end

  def create
    # The lookup and the mail both happen in the job, so a known and an
    # unknown address cost the same here: a synchronous branch would answer
    # faster for the unknown address and leak account existence.
    Users::PasswordResetJob.perform_later(params[:email_address].to_s)

    # Neutral either way: the response never reveals whether the address exists.
    redirect_to new_session_path, notice: t("passwords.create.sent")
  end

  def edit
  end

  def update
    # A password-less account reaches this page only through the operator's
    # setup link; its new password owes a second factor at once (PLAN_AUTH.md
    # §6.5), so the next password sign-in leads to enrolment.
    unless @user.password?
      @user.second_factor_required_since ||= Time.current - Allure::Auth::Config.second_factor_grace
    end
    attributes = password_params
    if attributes[:password].blank?
      # The model allows a nil password (provider accounts), so an empty
      # submission would otherwise "succeed" without changing anything.
      @user.errors.add(:password, :blank)
      render :edit, status: :unprocessable_content
    elsif @user.update(attributes)
      @user.sessions.destroy_all
      redirect_to new_session_path, notice: t("passwords.update.success")
    else
      # Rendered, not redirected: field errors stay attached to their inputs.
      render :edit, status: :unprocessable_content
    end
  end

  private
    # The form is built on the user model, so its fields arrive under `user`.
    def password_params
      params.fetch(:user, {}).permit(:password, :password_confirmation)
    end

    def set_user_by_token
      @user = User.find_by_password_reset_token!(params[:token])
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      redirect_to new_password_path, alert: t("passwords.token.invalid")
    end
end
