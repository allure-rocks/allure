# frozen_string_literal: true

# Registration (M4 Slice 1). Gated by Allure::Registration (ALLOW_REGISTRATION)
# unless a valid single-use invitation is presented: the operator generates one
# from the console, so a pre-production instance can invite one account at a
# time without opening self-registration. The closed branch blocks the form,
# creation, and availability with a plain statement instead of a dead link.
# Actors stay lazily provisioned on demand, so signup creates only the user row.
class RegistrationsController < ApplicationController
  layout "auth"

  allow_unauthenticated_access only: %i[new create availability]
  rate_limit to: 10, within: 3.minutes, only: %i[create availability],
    with: -> { redirect_to new_session_path, alert: t("registrations.create.rate_limited") }

  before_action :load_invitation
  before_action :require_registration_access

  def new
    @user = User.new(email_address: @invitation&.email_address, display_name: @invitation&.display_name)
  end

  def create
    @user = User.new(registration_attributes)
    if @user.save(context: :self_registration)
      @invitation&.accept!
      complete_sign_in @user, notice: t("registrations.create.success")
    else
      render :new, status: :unprocessable_content
    end
  rescue ActiveRecord::RecordNotUnique => error
    # Two concurrent signups can both pass the uniqueness validations before
    # either insert; the database index is the backstop. Report it as a field
    # error instead of letting the constraint violation become a 500.
    attribute = error.message.include?("index_users_on_email_address") ? :email_address : :username
    @user.errors.add(attribute, :taken)
    render :new, status: :unprocessable_content
  end

  # Live username availability for the sign-up form. Only the username
  # validations are reported; a candidate is never persisted here.
  def availability
    candidate = User.new(username: params[:username].to_s)
    candidate.valid?(:self_registration)
    messages = candidate.errors.full_messages_for(:username)

    render json: { available: messages.empty?, reason: messages.first }
  end

  private

  def load_invitation
    @invitation_token = params[:invitation_token].presence
    @invitation = RegistrationInvitation.find_by_token(@invitation_token)
  end

  def require_registration_access
    return if Allure::Registration.open?
    return if @invitation&.usable?

    if @invitation_token
      redirect_to new_session_path, alert: t("registrations.invitation.invalid")
    else
      redirect_to new_session_path, alert: t("registrations.closed")
    end
  end

  # The invitation address is authoritative: a submitted value is discarded so
  # the account always belongs to the address the operator invited. The new
  # account keeps the language the form was read in.
  def registration_attributes
    attributes = registration_params.merge(locale: I18n.locale.to_s)
    attributes[:email_address] = @invitation.email_address if @invitation
    attributes
  end

  def registration_params
    params.require(:user).permit(:username, :display_name, :email_address, :password, :password_confirmation)
  end
end
