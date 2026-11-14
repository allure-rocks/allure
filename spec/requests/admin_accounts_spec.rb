# frozen_string_literal: true

require "rails_helper"

# Account administration (PLAN_ADMIN.md §4.5, §7): search, suspension with
# session revocation, and reinstatement.
RSpec.describe "Admin accounts" do
  let(:operator) { create(:user, :with_totp, username: "operator") }
  let(:member) { create(:user, display_name: "Marie Rider") }

  around do |example|
    previous = ENV["INSTANCE_OPERATOR_USERNAME"]
    ENV["INSTANCE_OPERATOR_USERNAME"] = "operator"
    example.run
  ensure
    previous.nil? ? ENV.delete("INSTANCE_OPERATOR_USERNAME") : ENV["INSTANCE_OPERATOR_USERNAME"] = previous
  end

  describe "authorization" do
    it "redirects an anonymous visitor" do
      get admin_accounts_path

      expect(response).to redirect_to(new_session_path)
    end

    it "answers 404 to a member" do
      sign_in_as(member)

      get admin_accounts_path

      expect(response).to have_http_status(:not_found)
    end

    it "performs nothing for a member" do
      sign_in_as(member)

      post admin_account_suspend_path(member)

      expect(response).to have_http_status(:not_found)
      expect(member.reload).not_to be_suspended
      expect(AdminEvent.count).to eq(0)
    end
  end

  describe "index" do
    before { sign_in_as(operator) }

    it "lists accounts with activity counts" do
      create(:workout, user: member, sport: catalog_sport("running"))

      get admin_accounts_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Marie Rider", "@#{member.username}", member.email_address)
    end

    it "filters by search and state" do
      suspended = create(:user, username: "suspended_one", suspended_at: Time.current)

      get admin_accounts_path(q: "suspended_one")
      expect(response.body).to include("@suspended_one")
      expect(response.body).not_to include("@#{member.username}")

      get admin_accounts_path(state: "suspended")
      expect(response.body).to include("@suspended_one")
      expect(response.body).not_to include("@#{member.username}")

      get admin_accounts_path(state: "active")
      expect(response.body).to include("@#{member.username}")
      expect(response.body).not_to include("@suspended_one")
    end
  end

  describe "photo storage quota" do
    before { sign_in_as(operator) }

    it "sets and clears an override, auditing each change" do
      patch admin_account_photo_quota_path(member), params: { quota_mb: "4" }
      expect(response).to redirect_to(admin_account_path(member))
      expect(member.reload.photo_quota_bytes).to eq(4.megabytes)
      expect(AdminEvent.last).to have_attributes(action: "photo_quota_changed", metadata: { "quota_bytes" => 4.megabytes })
      patch admin_account_photo_quota_path(member), params: { quota_mb: "" }
      expect(member.reload.photo_quota_bytes).to be_nil
    end

    it "allows zero, but rejects negative and fractional values without auditing" do
      patch admin_account_photo_quota_path(member), params: { quota_mb: "0" }
      expect(member.reload.photo_quota_bytes).to eq(0)
      %w[-1 1.5 bogus].each do |value|
        expect { patch admin_account_photo_quota_path(member), params: { quota_mb: value } }.not_to change(AdminEvent, :count)
        expect(member.reload.photo_quota_bytes).to eq(0)
      end
    end

    it "refuses a non-operator" do
      sign_in_as(member)
      patch admin_account_photo_quota_path(member), params: { quota_mb: "4" }
      expect(response).to have_http_status(:not_found)
      expect(member.reload.photo_quota_bytes).to be_nil
    end
  end

  describe "suspension" do
    before { sign_in_as(operator) }

    it "suspends an account, revokes its sessions, and audits" do
      member.sessions.create!(user_agent: "browser", ip_address: "127.0.0.1")

      post admin_account_suspend_path(member),
           params: { account: { suspension_reason: "Spam reports" } }

      expect(response).to redirect_to(admin_account_path(member))
      expect(member.reload).to be_suspended
      expect(member.suspension_reason).to eq("Spam reports")
      expect(member.sessions.count).to eq(0)
      expect(AdminEvent.last).to have_attributes(action: "account_suspended", user: operator)
    end

    it "refuses to suspend the operator account" do
      post admin_account_suspend_path(operator)

      expect(response).to redirect_to(admin_account_path(operator))
      expect(flash[:alert]).to eq(I18n.t("admin.accounts.flash.self_suspend"))
      expect(operator.reload).not_to be_suspended
      expect(AdminEvent.count).to eq(0)
    end

    it "reinstates a suspended account and audits" do
      member.update!(suspended_at: Time.current, suspension_reason: "mistake")

      post admin_account_reinstate_path(member)

      expect(response).to redirect_to(admin_account_path(member))
      expect(member.reload).not_to be_suspended
      expect(member.suspension_reason).to be_nil
      expect(AdminEvent.last).to have_attributes(action: "account_reinstated")
    end
  end

  describe "suspended sign-in" do
    it "refuses valid credentials with a dedicated message" do
      member.update!(suspended_at: Time.current)

      post session_path, params: { email_address: member.email_address, password: "allure-test-password" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("sessions.create.suspended")))
      expect(member.sessions.count).to eq(0)
    end

    it "revokes an existing session on the next request" do
      sign_in_as(member)
      expect(member.sessions.count).to eq(1)

      member.update!(suspended_at: Time.current)
      get me_path

      expect(response).to redirect_to(new_session_path)
      expect(member.sessions.count).to eq(0)
    end
  end

  describe "scheduled deletion (PLAN_ACCOUNT.md §4.4)" do
    before { sign_in_as(operator) }

    it "schedules a member's deletion, signs them out everywhere, and audits" do
      member.sessions.create!(user_agent: "browser", ip_address: "127.0.0.1")

      post admin_account_deletion_path(member)

      expect(response).to redirect_to(admin_account_path(member))
      expect(member.reload).to have_attributes(deletion_requested_by: "operator")
      expect(member.deletion_scheduled_at).to be_within(1.minute).of(7.days.from_now)
      expect(member.sessions.count).to eq(0)
      expect(AdminEvent.last).to have_attributes(action: "account_deletion_scheduled", user: operator)

      get admin_account_path(member)
      expect(response.body).to include(I18n.t("admin.accounts.states.deletion_scheduled"))
    end

    it "cancels it and audits" do
      Users::DeletionSchedule.new(user: member).schedule!(by: "operator")

      delete admin_account_deletion_path(member)

      expect(member.reload).not_to be_deletion_scheduled
      expect(AdminEvent.last).to have_attributes(action: "account_deletion_cancelled")
    end

    it "refuses a deletion whose purge has started" do
      member.update!(deletion_requested_at: 8.days.ago, deletion_scheduled_at: 1.day.ago,
                     deletion_requested_by: "self", deletion_started_at: 1.minute.ago)

      delete admin_account_deletion_path(member)

      expect(flash[:alert]).to eq(I18n.t("admin.accounts.flash.deletion_started"))
      expect(member.reload).to be_deletion_scheduled
    end

    it "never deletes the operator account" do
      post admin_account_deletion_path(operator)

      expect(flash[:alert]).to eq(I18n.t("admin.accounts.flash.self_deletion"))
      expect(operator.reload).not_to be_deletion_scheduled
    end
  end
end
