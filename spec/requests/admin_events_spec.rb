# frozen_string_literal: true

require "rails_helper"

# The audit log panel (PLAN_ADMIN.md §4.9): newest first, filterable, read-only.
RSpec.describe "Admin events" do
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
      get admin_events_path

      expect(response).to redirect_to(new_session_path)
    end

    it "answers 404 to a member" do
      sign_in_as(member)

      get admin_events_path

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "panel" do
    before { sign_in_as(operator) }

    it "lists audited actions with actor and metadata" do
      Admin::Audit.record(actor: operator, action: :domain_blocked, metadata: { "domain" => "blocked.example" })

      get admin_events_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("admin.events.actions.domain_blocked"))
      expect(response.body).to include("@#{operator.username}", "blocked.example")
    end

    it "filters by action" do
      Admin::Audit.record(actor: operator, action: :domain_blocked, metadata: { "domain" => "blocked.example" })
      Admin::Audit.record(actor: operator, action: :queue_paused, metadata: { "queue" => "default" })

      get admin_events_path(kind: "queue_paused")

      expect(response.body).to include(I18n.t("admin.events.actions.queue_paused"))
      expect(response.body).not_to include("blocked.example")
    end
  end
end
