# frozen_string_literal: true

require "rails_helper"

# Single-use, email-bound invitations let a closed instance admit one account
# without opening self-registration (RegistrationsController + users:invite).
RSpec.describe "Registration invitations" do
  before { allow(Allure::Registration).to receive(:open?).and_return(false) }

  def issue_invitation(email_address = "invitee@allure.test")
    RegistrationInvitation.issue(email_address:)
  end

  def signup_params(email_address: "invitee@allure.test")
    {
      user: {
        username: "invitee",
        email_address:,
        password: "allure-test-password",
        password_confirmation: "allure-test-password"
      }
    }
  end

  it "opens the sign-up form with the bound address prefilled and read-only" do
    _, token = issue_invitation

    get new_registration_path(invitation_token: token)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(%(name="invitation_token"), %(value="#{token}"))
    expect(response.body).to include(%(value="invitee@allure.test"), "readonly")
    expect(response.body).to include("Adresse fixée par")
  end

  it "prefills the display name chosen by the operator and keeps the invitee's edit" do
    invitation, token = RegistrationInvitation.issue(email_address: "invitee@allure.test", display_name: "Jeanne Martin")

    get new_registration_path(invitation_token: token)
    expect(response.body).to include(%(value="Jeanne Martin"))

    params = signup_params
    params[:user][:display_name] = "Jeanne M."
    post registration_path, params: params.merge(invitation_token: token)

    expect(User.last.display_name).to eq("Jeanne M.")
    expect(invitation.reload).to be_accepted
  end

  it "carries the token into live username availability" do
    _, token = issue_invitation

    get availability_registration_path(invitation_token: token),
        params: { username: "freshname" }, headers: { "Accept" => "application/json" }

    expect(response.parsed_body).to eq({ "available" => true, "reason" => nil })
  end

  it "creates the account with the bound address and consumes the invitation" do
    invitation, token = issue_invitation

    expect do
      post registration_path, params: signup_params(email_address: "someone.else@allure.test").merge(invitation_token: token)
    end.to change(User, :count).by(1)

    expect(response).to redirect_to(me_url)
    expect(User.last.email_address).to eq("invitee@allure.test")
    expect(invitation.reload.accepted_at).to be_present
  end

  it "keeps the token on a failed signup so the form can be corrected" do
    _, token = issue_invitation

    expect do
      post registration_path, params: {
        invitation_token: token,
        user: { username: "admin", email_address: "invitee@allure.test",
                password: "too-short", password_confirmation: "too-short" }
      }
    end.not_to change(User, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include(%(name="invitation_token"), %(value="#{token}"))
  end

  it "refuses an expired invitation" do
    invitation, token = issue_invitation
    invitation.update!(expires_at: 1.minute.ago)

    get new_registration_path(invitation_token: token)

    expect(response).to redirect_to(new_session_path)
    expect(flash[:alert]).to eq(I18n.t("registrations.invitation.invalid"))

    expect do
      post registration_path, params: signup_params.merge(invitation_token: token)
    end.not_to change(User, :count)
  end

  it "refuses an already accepted invitation" do
    invitation, token = issue_invitation
    invitation.accept!

    get new_registration_path(invitation_token: token)

    expect(response).to redirect_to(new_session_path)
    expect(flash[:alert]).to eq(I18n.t("registrations.invitation.invalid"))
  end

  it "refuses a forged token" do
    issue_invitation

    get new_registration_path(invitation_token: "forged-token")

    expect(response).to redirect_to(new_session_path)
    expect(flash[:alert]).to eq(I18n.t("registrations.invitation.invalid"))
    expect(RegistrationInvitation.pending.count).to eq(1)
  end

  it "keeps the plain closed message when no token is presented" do
    get new_registration_path

    expect(response).to redirect_to(new_session_path)
    expect(flash[:alert]).to eq(I18n.t("registrations.closed"))
  end
end
