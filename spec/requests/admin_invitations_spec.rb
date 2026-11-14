# frozen_string_literal: true

require "rails_helper"

# Registration invitations (PLAN_ADMIN.md §4.6, §8): issue a single-use link,
# show it exactly once, and revoke it.
RSpec.describe "Admin invitations" do
  let(:operator) { create(:user, :with_totp, username: "operator") }
  let(:member) { create(:user) }

  around do |example|
    previous = ENV["INSTANCE_OPERATOR_USERNAME"]
    ENV["INSTANCE_OPERATOR_USERNAME"] = "operator"
    example.run
  ensure
    previous.nil? ? ENV.delete("INSTANCE_OPERATOR_USERNAME") : ENV["INSTANCE_OPERATOR_USERNAME"] = previous
  end

  describe "authorization" do
    it "redirects an anonymous visitor" do
      get admin_invitations_path

      expect(response).to redirect_to(new_session_path)
    end

    it "answers 404 to a member" do
      sign_in_as(member)

      get admin_invitations_path

      expect(response).to have_http_status(:not_found)
    end

    it "performs nothing for a member" do
      sign_in_as(member)

      post admin_invitations_path, params: { invitation: { email_address: "new@allure.test" } }

      expect(response).to have_http_status(:not_found)
      expect(RegistrationInvitation.count).to eq(0)
      expect(AdminEvent.count).to eq(0)
    end
  end

  describe "index" do
    before { sign_in_as(operator) }

    it "lists invitations with their state" do
      create(:registration_invitation, email_address: "pending@allure.test")
      create(:registration_invitation, :accepted, email_address: "accepted@allure.test")

      get admin_invitations_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("pending@allure.test", "accepted@allure.test")
      expect(response.body).to include(I18n.t("admin.invitations.states.pending"))
    end
  end

  describe "creation" do
    before { sign_in_as(operator) }

    it "issues a usable link, shows it once, and audits" do
      post admin_invitations_path,
           params: { invitation: { email_address: "New@Allure.Test", expires_in_days: 3 } }

      expect(response).to have_http_status(:created)
      invitation = RegistrationInvitation.last
      expect(invitation.email_address).to eq("new@allure.test")

      token = response.body[%r{invitation_token=([^"&]+)}, 1]
      expect(token).to be_present
      expect(RegistrationInvitation.find_by_token(token)).to eq(invitation)
      expect(AdminEvent.last).to have_attributes(action: "invitation_created", user: operator)
    end

    it "offers an optional display name field" do
      get admin_new_invitation_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(name="invitation[display_name]"))
    end

    it "stores an optional display name, lists it, and audits it" do
      post admin_invitations_path,
           params: { invitation: { email_address: "new@allure.test", display_name: "  Jeanne   Martin " } }

      expect(response).to have_http_status(:created)
      expect(RegistrationInvitation.last.display_name).to eq("Jeanne Martin")
      expect(AdminEvent.last.metadata).to include("display_name" => "Jeanne Martin")

      get admin_invitations_path
      expect(response.body).to include("Jeanne Martin")
    end

    it "rejects a display name over 60 characters" do
      post admin_invitations_path,
           params: { invitation: { email_address: "new@allure.test", display_name: "x" * 61 } }

      expect(response).to redirect_to(admin_new_invitation_path)
      expect(flash[:alert]).to eq(I18n.t("admin.invitations.flash.invalid_display_name"))
      expect(RegistrationInvitation.count).to eq(0)
    end

    it "clamps the expiry to the maximum" do
      post admin_invitations_path,
           params: { invitation: { email_address: "new@allure.test", expires_in_days: 365 } }

      expect(RegistrationInvitation.last.expires_at).to be <= 31.days.from_now
    end

    it "rejects an email that already has an account" do
      post admin_invitations_path, params: { invitation: { email_address: member.email_address } }

      expect(response).to redirect_to(admin_new_invitation_path)
      expect(flash[:alert]).to eq(I18n.t("admin.invitations.flash.account_exists"))
      expect(RegistrationInvitation.count).to eq(0)
    end

    it "rejects an invalid email" do
      post admin_invitations_path, params: { invitation: { email_address: "not-an-email" } }

      expect(response).to redirect_to(admin_new_invitation_path)
      expect(RegistrationInvitation.count).to eq(0)
    end
  end

  describe "revocation" do
    before { sign_in_as(operator) }

    it "deletes the invitation and audits" do
      invitation = create(:registration_invitation, email_address: "revoked@allure.test")

      delete admin_invitation_path(invitation)

      expect(response).to redirect_to(admin_invitations_path)
      expect(RegistrationInvitation.exists?(invitation.id)).to be(false)
      expect(AdminEvent.last).to have_attributes(action: "invitation_revoked")
    end
  end
end
