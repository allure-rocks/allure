# frozen_string_literal: true

require "rails_helper"

# Development-only impersonation (AGENTS.md, "Development tools"): the operator
# opens a session as another account from /devtools/impersonation, and the bar
# above the topbar hands the browser back. The engine is never loaded in
# production, so neither these routes nor their views exist there.
RSpec.describe "DevTools impersonation" do
  let(:operator) { create(:user, :with_totp, username: "operator") }
  # Created up front: several examples assert on the list before touching it.
  let!(:member) { create(:user, username: "member") }

  around do |example|
    previous = ENV["INSTANCE_OPERATOR_USERNAME"]
    ENV["INSTANCE_OPERATOR_USERNAME"] = "operator"
    example.run
  ensure
    previous.nil? ? ENV.delete("INSTANCE_OPERATOR_USERNAME") : ENV["INSTANCE_OPERATOR_USERNAME"] = previous
  end

  # The row's own control, so a name appearing in the topbar cannot satisfy it.
  def start_control(username)
    I18n.t("dev_tools.impersonations.show.start_aria", username:)
  end

  describe "authorization" do
    it "redirects an anonymous visitor to sign-in" do
      get devtools_impersonation_path

      expect(response).to redirect_to(new_session_path)
    end

    it "answers 404 to a member" do
      sign_in_as(member)

      get devtools_impersonation_path

      expect(response).to have_http_status(:not_found)
    end

    it "does not let a member open a session" do
      sign_in_as(member)

      expect {
        post devtools_impersonation_path, params: { user_id: operator.id }
      }.not_to change(Session, :count)

      expect(response).to have_http_status(:not_found)
    end

    it "keeps the entry out of a member's account menu" do
      sign_in_as(member)

      get me_path

      expect(response.body).not_to include(I18n.t("dev_tools.menu"))
    end
  end

  describe "the operator's list" do
    before { sign_in_as(operator) }

    it "lists the accounts, its own excluded" do
      get devtools_impersonation_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(start_control("member"))
      expect(response.body).not_to include(start_control("operator"))
    end

    it "hides suspended accounts" do
      create(:user, username: "paused", suspended_at: 1.day.ago)

      get devtools_impersonation_path

      expect(response.body).not_to include(start_control("paused"))
    end

    it "shows the entry in the account menu" do
      get me_path

      expect(response.body).to include(I18n.t("dev_tools.menu"))
    end
  end

  describe "starting an impersonation" do
    before { sign_in_as(operator) }

    it "opens a session as the target and shows the bar" do
      expect {
        post devtools_impersonation_path, params: { user_id: member.id }
      }.to change { member.sessions.count }.by(1)

      expect(response).to redirect_to(me_path)
      expect(Session.where(user: operator).count).to eq(1)

      follow_redirect!

      expect(response.body).to include(I18n.t("dev_tools.bar.copy", username: "member"))
      expect(response.body).to include(I18n.t("dev_tools.bar.stop", operator: "operator"))
    end

    it "renders the bar in the other locale" do
      post devtools_impersonation_path, params: { user_id: member.id }

      get me_path(locale: "en")

      expect(response.body).to include(I18n.t("dev_tools.bar.copy", username: "member", locale: :en))
    end

    it "asks for a second factor once the step-up went stale" do
      operator.sessions.sole.update!(second_factor_at: 1.hour.ago)

      expect {
        post devtools_impersonation_path, params: { user_id: member.id }
      }.not_to change(Session, :count)

      expect(response).to redirect_to(new_reauthentication_path)
    end

    it "refuses the operator's own account" do
      expect {
        post devtools_impersonation_path, params: { user_id: operator.id }
      }.not_to change(Session, :count)

      expect(response).to redirect_to(devtools_impersonation_path)
      expect(flash[:alert]).to eq(I18n.t("dev_tools.impersonations.create.self_refused"))
    end

    it "refuses a suspended account" do
      suspended = create(:user, username: "paused", suspended_at: 1.day.ago)

      expect {
        post devtools_impersonation_path, params: { user_id: suspended.id }
      }.not_to change(Session, :count)

      expect(response).to redirect_to(devtools_impersonation_path)
      expect(flash[:alert]).to eq(I18n.t("dev_tools.impersonations.create.suspended_refused"))
    end
  end

  describe "ending an impersonation" do
    before do
      sign_in_as(operator)
      post devtools_impersonation_path, params: { user_id: member.id }
    end

    it "destroys the impersonated session and resumes the operator" do
      impersonated = member.sessions.sole

      expect {
        delete devtools_impersonation_path
      }.to change { Session.exists?(impersonated.id) }.from(true).to(false)

      expect(response).to redirect_to(devtools_impersonation_path)
      follow_redirect!
      expect(response.body).to include(I18n.t("dev_tools.impersonations.destroy.stopped", username: "operator"))

      get me_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("@operator")
      expect(response.body).not_to include(I18n.t("dev_tools.bar.copy", username: "member"))
    end

    it "returns to the operator when signing out while impersonating" do
      impersonated = member.sessions.sole

      delete session_path

      expect(Session.exists?(impersonated.id)).to be(false)
      expect(Session.where(user: operator).count).to eq(1)

      get me_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("@operator")
    end

    it "answers 404 when no impersonation is active" do
      delete devtools_impersonation_path # ends it

      delete devtools_impersonation_path

      expect(response).to have_http_status(:not_found)
    end

    it "speaks the operator's locale in the notice, not the target's" do
      sign_in_as(operator)
      other = create(:user, username: "other", locale: "en")
      post devtools_impersonation_path, params: { user_id: other.id }

      delete devtools_impersonation_path
      follow_redirect!

      expect(response.body).to include(
        I18n.t("dev_tools.impersonations.destroy.stopped", username: "operator", locale: :fr)
      )
    end

    it "forgets the way back when someone signs in during an impersonation" do
      other = create(:user, :with_totp, username: "other")

      sign_in_as(other)

      get me_path
      expect(response.body).to include("@other")
      expect(response.body).not_to include(I18n.t("dev_tools.bar.stop", operator: "operator"))

      delete devtools_impersonation_path
      expect(response).to have_http_status(:not_found)
    end

    it "keeps the administration console out of reach" do
      get admin_root_path

      expect(response).to have_http_status(:not_found)
    end
  end
end
