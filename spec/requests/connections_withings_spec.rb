# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Connected services: Withings" do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }

  around { |example| with_remote_import_enabled("withings") { example.run } }

  before { sign_in_as(user) }

  it "has no page while the operator has not enabled the provider" do
    with_remote_import_enabled("withings", enabled: false) do
      get connection_path("withings")
    end

    expect(response).to redirect_to(connections_path)
  end

  it "asks for the e-mail and the password only, and signs in in the background" do
    get connection_path("withings")
    expect(response.body).to include(%(id="withings_password"))
    expect(response.body).not_to include(%(id="retrieval_from_withings"))
    expect(response.body).to include(ERB::Util.h(I18n.t("settings.connections.withings.privacy")))

    expect do
      post connection_link_path("withings"),
           params: { email: "rider@example.test", password: "secret-pass",
                     retrieval: { from: "2026-08-01", to: "2026-08-31" } }
    end.to have_enqueued_job(ImportConnections::Withings::LinkJob)

    expect(user.import_connections.sole).to have_attributes(provider: "withings", status: "pending")
    expect(enqueued_jobs.last[:args].to_s).not_to include("secret-pass")
    expect(enqueued_jobs.last[:args].to_s).not_to include("2026-08-01")
    expect(user.workout_import_batches).to be_empty

    get connection_path("withings")
    expect(response.body).to include(I18n.t("settings.connections.withings.signing_in"))
  end

  it "offers to reconnect and resume when a session ended mid-batch" do
    connection = create(:import_connection, :linked, user:, provider: "withings",
                                                     credentials: { "sessionid" => "S1", "userid" => 7 })
    ImportConnections::Expiry.new(connection, notify: false).call
    batch = create(:workout_import_batch, user:, source: "withings", import_connection: connection,
                                          status: "queued", trigger: "scheduled")
    create(:workout_import_entry, batch:, external_id: "501", status: "queued")
    create(:workout_import_entry, batch:, external_id: "502", status: "queued")

    get connection_path("withings")

    expect(response.body).to include(I18n.t("settings.connections.withings.resume"))
    expect(response.body).to include(I18n.t("settings.connections.withings.pending_entries", count: 2))
    expect(response.body).to include(ERB::Util.h(I18n.t("settings.connections.withings.errors.session_ended")))
    expect(response.body).not_to include(%(id="retrieval_from_withings"))
  end

  describe "a linked account" do
    let!(:connection) do
      create(:import_connection, :linked, user:, provider: "withings", external_account_id: "7",
                                          external_account_name: "rider@example.test",
                                          token_expires_at: 24.hours.from_now,
                                          credentials: { "sessionid" => "S1", "userid" => 7 })
    end

    it "offers the ordinary retrieval without a password and names the session's end" do
      get connection_path("withings")

      expect(response.body).to include(ERB::Util.h(I18n.t("settings.connections.valid_until")))
      zone = Time.find_zone(user.time_zone) || Time.zone
      expect(response.body).to include(ERB::Util.h(I18n.l(connection.token_expires_at.in_time_zone(zone), format: :long)))
      expect(response.body).not_to include(%(id="withings_password"))
      expect(response.body).to include(%(id="retrieval_sport_withings"))
      expect(response.body).not_to include(connection_equipment_path("withings"))
      expect(response.body).to include(I18n.t("settings.connections.unlink.delete_workouts", provider: "Withings", count: 0))
    end

    it "shows the positioned-only switch and saves it" do
      get connection_path("withings")

      expect(response.body).to include(ERB::Util.h(I18n.t("settings.connections.preferences.positioned_only")))
      expect(connection.reload.positioned_only?).to be(true)

      patch connection_path("withings"),
            params: { import_connection: { auto_sync: "1", positioned_only: "0" } }

      expect(connection.reload.positioned_only?).to be(false)
    end

    it "retrieves a range with the fallback sport" do
      expect do
        post connection_retrievals_path("withings"),
             params: { retrieval: { from: "2026-08-01", to: "2026-08-31", sport_id: catalog_sport("cycling").id } }
      end.to have_enqueued_job(Workouts::RemoteImportBatchJob)

      expect(connection.import_batches.sole).to have_attributes(source: "withings", sport: catalog_sport("cycling"))
    end
  end

  it "marks a batch whose session died as waiting for a reconnection" do
    connection = create(:import_connection, :linked, user:, provider: "withings",
                                                     credentials: { "sessionid" => "S1", "userid" => 7 })
    connection.update!(status: "expired")
    batch = create(:workout_import_batch, user:, source: "withings", import_connection: connection,
                                           status: "queued", trigger: "scheduled")
    create(:workout_import_entry, batch:, external_id: "501", status: "queued")

    get workout_import_path(batch)

    expect(response.body).to include(I18n.t("workouts.batch_import.status.session_ended", provider: "Withings"))
    expect(response.body).to include(I18n.t("workouts.batch_import.status.reconnect"))
  end
end
