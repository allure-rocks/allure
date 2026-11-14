class SessionsController < ApplicationController
  layout "auth"

  allow_unauthenticated_access only: %i[ new create ]
  allow_enrolment_only_access only: :destroy
  allow_deletion_window_access only: :destroy
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: t("sessions.create.rate_limited") }

  def new
  end

  def create
    user = authenticate_by_credentials
    if user&.suspended?
      # Verified credentials, refused access: the message names the reason
      # without confirming anything to a caller who cannot authenticate.
      flash.now[:alert] = t("sessions.create.suspended")
      render :new, status: :unprocessable_content
    elsif user
      begin_sign_in user
    else
      # Rendered, not redirected: the email persists and the summary alert is
      # announced to assistive technology on the same page.
      flash.now[:alert] = t("sessions.create.invalid")
      render :new, status: :unprocessable_content
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, status: :see_other
  end

  private

    # `User.authenticate_by` raises when either side of the pair is absent, so
    # a crafted POST must be answered like any other failed sign-in.
    def authenticate_by_credentials
      credentials = params.permit(:email_address, :password)
      return unless credentials[:email_address].present? && credentials[:password].present?

      User.authenticate_by(credentials)
    end
end
