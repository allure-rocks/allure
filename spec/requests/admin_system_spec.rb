# frozen_string_literal: true

require "rails_helper"

# System diagnostics (docs/dev/ADMIN.md): versions, database sizes, storage
# and environment flags, never a secret value.
RSpec.describe "Admin system" do
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
      get admin_system_path

      expect(response).to redirect_to(new_session_path)
    end

    it "answers 404 to a member" do
      sign_in_as(member)

      get admin_system_path

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "panel" do
    before { sign_in_as(operator) }

    it "renders versions, databases, storage and environment flags" do
      get admin_system_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("admin.system.title"))
      expect(response.body).to include(Allure::VERSION)
      expect(response.body).to include(Rails.version)
      expect(response.body).to include(I18n.t("admin.system.federation_base_url"))
      expect(response.body).to include(I18n.t("admin.system.registration_open"))
    end

    it "never renders a secret value" do
      get admin_system_path

      expect(response.body).not_to include(Rails.application.secret_key_base)
      expect(response.body).not_to match(/password|secret_key/i)
    end
  end
end
