# frozen_string_literal: true

require "rails_helper"

# The « Connexions » tab of the imports panel (docs/dev/REMOTE-IMPORTS.md):
# every connection's state without its secrets, and the audited revocation.
RSpec.describe "Admin import connections" do
  let(:operator) { create(:user, :with_totp, username: "operator") }
  let(:member) { create(:user, username: "rower") }

  around do |example|
    previous = ENV["INSTANCE_OPERATOR_USERNAME"]
    ENV["INSTANCE_OPERATOR_USERNAME"] = "operator"
    with_remote_import_enabled { example.run }
  ensure
    previous.nil? ? ENV.delete("INSTANCE_OPERATOR_USERNAME") : ENV["INSTANCE_OPERATOR_USERNAME"] = previous
  end

  it "answers 404 to a member" do
    sign_in_as(member)

    get admin_import_connections_path
    expect(response).to have_http_status(:not_found)

    post admin_import_connection_revoke_path(create(:import_connection, :linked, user: member))
    expect(response).to have_http_status(:not_found)
  end

  describe "panel" do
    let!(:connection) do
      create(:import_connection, :linked, user: member, external_account_name: "Secret Name",
                                          last_sync_error: "Garmin ne répond pas.")
    end

    before { sign_in_as(operator) }

    it "lists connections with their state and never their secrets or external account" do
      create(:workout, user: member, import_connection: connection, external_id: "1")
      create(:import_connection, provider: "exr", user: create(:user), status: "expired")

      get admin_import_connections_path

      expect(response.body).to include("@rower", "Garmin Connect", "EXR", "Garmin ne répond pas.")
      expect(response.body).not_to include("Secret Name", "access", "refresh", connection.external_account_id)

      get admin_import_connections_path(provider: "exr")
      expect(response.body).not_to include("@rower")
    end

    it "revokes, cancels running batches, notifies the owner and audits" do
      batch = create(:workout_import_batch, user: member, sport: nil, source: "garmin_connect",
                                            import_connection: connection, status: "processing")
      workout = create(:workout, user: member, import_connection: connection, external_id: "1")

      post admin_import_connection_revoke_path(connection)

      expect(response).to redirect_to(admin_import_connections_path)
      expect(connection.reload).to have_attributes(status: "revoked", credentials: {}, revoked_at: be_present)
      expect(batch.reload.cancellation_requested?).to be(true)
      expect(Workout.exists?(workout.id)).to be(true)
      notification = Notification.find_by!(user: member, kind: "import_connection_revoked", subject: connection)
      expect(notification.payload).to include("by" => "operator")
      expect(AdminEvent.where(action: "import_connection_revoked", subject: connection).sole.metadata)
        .to eq("provider" => "garmin_connect", "owner" => "rower")

      sign_in_as(member)
      get notifications_path
      expect(response.body).to include(ERB::Util.h(I18n.t("notifications.kinds.import_connection_revoked_operator", provider: "Garmin Connect")))
    end

    it "refuses a connection that is no longer active" do
      connection.update!(status: "unlinked", credentials: {})

      post admin_import_connection_revoke_path(connection)

      expect(flash[:alert]).to eq(I18n.t("admin.imports.connections.flash.not_revocable"))
      expect(AdminEvent.where(action: "import_connection_revoked")).to be_empty
    end
  end

  describe "batch list" do
    before { sign_in_as(operator) }

    it "filters by source and shows the trigger" do
      connection = create(:import_connection, :linked, user: member)
      create(:workout_import_batch, user: member, sport: nil, source: "garmin_connect", import_connection: connection,
                                    trigger: "scheduled")
      create(:workout_import_batch, user: create(:user, username: "filer"))

      get admin_imports_path(source: "garmin_connect")

      expect(response.body).to include("@rower", I18n.t("admin.imports.triggers.scheduled"))
      expect(response.body).not_to include("@filer")
    end
  end
end
