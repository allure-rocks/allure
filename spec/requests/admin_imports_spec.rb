# frozen_string_literal: true

require "rails_helper"

# Import failure inspection (docs/dev/ADMIN.md): the batch list and the stored
# per-entry parser detail.
RSpec.describe "Admin imports" do
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
      get admin_imports_path

      expect(response).to redirect_to(new_session_path)
    end

    it "answers 404 to a member" do
      sign_in_as(member)

      get admin_imports_path

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "panel" do
    before { sign_in_as(operator) }

    it "lists batches with their counters and filters by status" do
      other = create(:user, username: "other_rider")
      create(:workout_import_batch, user: member, status: "failed", total_entries: 3, failed_entries: 2)
      create(:workout_import_batch, user: other, status: "completed", total_entries: 1, imported_entries: 1)

      get admin_imports_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("@#{member.username}", "@#{other.username}")

      get admin_imports_path(status: "completed")
      expect(response.body).to include("@#{other.username}")
      expect(response.body).not_to include("@#{member.username}")
    end

    it "shows the stored parser detail of a failed entry" do
      batch = create(:workout_import_batch, user: member, status: "failed")
      create(:workout_import_entry, batch:, position: 0, source_name: "broken.gpx",
             status: "failed", error_message: "malformed XML at line 4")

      get admin_import_path(batch)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("broken.gpx", "malformed XML at line 4")
    end
  end
end
