# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Connected services actions" do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }

  around { |example| with_remote_import_enabled { example.run } }

  before { sign_in_as(user) }

  describe "linking Garmin Connect" do
    it "starts a background sign-in holding the password only in the encrypted row" do
      expect do
        post connection_link_path("garmin_connect"), params: { email: "rider@example.test", password: "secret", region: "cn" }
      end.to have_enqueued_job(ImportConnections::GarminConnect::LinkJob)

      connection = user.import_connections.sole
      expect(connection).to have_attributes(status: "pending", region: "cn")
      expect(enqueued_jobs.last[:args].to_s).not_to include("secret")
      expect(ImportConnection.connection.select_value("SELECT credentials FROM import_connections")).not_to include("secret")
      expect(response).to redirect_to(connection_path("garmin_connect"))

      get connection_path("garmin_connect")
      expect(response.body).to include(I18n.t("settings.connections.garmin_connect.signing_in"))
      expect(response.body).not_to include("data-live-frame-done")
    end

    it "offers the code field and accepts the code" do
      connection = create(:import_connection, user:, status: "mfa_pending", pending_expires_at: 5.minutes.from_now,
                                              credentials: { "mfa_state" => { "flow" => "mobile" }, "mfa_method" => "email" })

      get connection_path("garmin_connect")
      expect(response.body).to include(%(autocomplete="one-time-code"))
      expect(response.body).to include("data-live-frame-done")

      expect { post connection_mfa_path("garmin_connect"), params: { code: "123456" } }
        .to have_enqueued_job(ImportConnections::GarminConnect::LinkJob)
      expect(connection.reload.credential(:pending_mfa_code)).to eq("123456")
    end

    it "cancels an attempt" do
      create(:import_connection, user:, status: "pending", pending_expires_at: 5.minutes.from_now,
                                 credentials: { "pending_password" => "secret", "return_status" => "expired" })

      delete connection_link_path("garmin_connect")

      expect(user.import_connections.sole).to have_attributes(status: "expired", credentials: {})
    end

    it "refuses a second link while one is linked" do
      create(:import_connection, :linked, user:)

      post connection_link_path("garmin_connect"), params: { email: "a@b.test", password: "x" }

      expect(flash[:alert]).to eq(I18n.t("settings.connections.link.not_allowed"))
      expect(user.import_connections.sole.status).to eq("linked")
    end

    it "answers 404 while the operator disables the provider" do
      with_remote_import_enabled(enabled: false) do
        post connection_link_path("garmin_connect"), params: { email: "a@b.test", password: "x" }
      end

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "a linked connection" do
    let!(:connection) { create(:import_connection, :linked, user:) }

    it "renders the retrieval, the preferences and the unlink choice" do
      get connection_path("garmin_connect")

      expect(response.body).to include(connection_retrievals_path("garmin_connect"))
      expect(response.body).to include(%(name="delete_data"), "checked")
      expect(response.body).to include("data-live-frame-done")
    end

    it "starts a retrieval and shows its batch" do
      expect do
        post connection_retrievals_path("garmin_connect"),
             params: { retrieval: { from: "2026-09-01", to: "2026-09-30", sport_id: catalog_sport("cycling").id } }
      end.to have_enqueued_job(Workouts::RemoteImportBatchJob)

      batch = connection.import_batches.sole
      expect(batch).to have_attributes(range_from: Date.new(2026, 9, 1), range_to: Date.new(2026, 9, 30), trigger: "manual")
      expect(response).to redirect_to(workout_import_path(batch))
    end

    it "refuses a range in the wrong order" do
      post connection_retrievals_path("garmin_connect"), params: { retrieval: { from: "2026-09-30", to: "2026-09-01" } }

      expect(flash[:alert]).to eq(I18n.t("settings.connections.retrieval.errors.invalid_range"))
      expect(connection.import_batches).to be_empty
    end

    it "saves the preferences" do
      patch connection_path("garmin_connect"),
            params: { import_connection: { auto_sync: "0", fallback_sport_id: catalog_sport("running").id } }

      expect(connection.reload).to have_attributes(auto_sync: false, fallback_sport: catalog_sport("running"))
    end

    it "syncs and retrieves equipment on demand" do
      expect { post connection_sync_path("garmin_connect") }
        .to have_enqueued_job(ImportConnections::SyncJob).with(connection, manual: true)
      expect { post connection_equipment_path("garmin_connect") }
        .to have_enqueued_job(ImportConnections::EquipmentSyncJob)
      expect(connection.reload.sync_equipment).to be(true)
    end

    it "unlinks with the owner's deletion choice and cancels running batches" do
      batch = create(:workout_import_batch, user:, sport: nil, source: "garmin_connect", import_connection: connection,
                                            status: "processing")

      expect { delete connection_path("garmin_connect"), params: { delete_data: "0" } }
        .to have_enqueued_job(ImportConnections::UnlinkJob).with(connection, delete_data: false)

      expect(connection.reload.status).to eq("unlinking")
      expect(batch.reload.cancellation_requested?).to be(true)
    end
  end

  it "never reaches another account's connection" do
    create(:import_connection, :linked)

    patch connection_path("garmin_connect"), params: { import_connection: { auto_sync: "0" } }

    expect(response).to have_http_status(:not_found)
  end

  it "notifies through the inbox switch" do
    connection = create(:import_connection, :linked, user:)
    ImportConnections::Expiry.new(connection).call

    get notifications_path
    expect(response.body).to include(I18n.t("notifications.kinds.import_connection_expired", provider: "Garmin Connect"))

    patch settings_notifications_path, params: { user: { notify_import_connections: "0" } }
    expect(user.reload.notify_import_connections).to be(false)
  end
end
