# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Connected services: Zwift" do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }

  around { |example| with_remote_import_enabled("zwift") { example.run } }

  before { sign_in_as(user) }

  it "has no page while the operator has not enabled the provider" do
    with_remote_import_enabled("zwift", enabled: false) do
      get connection_path("zwift")
    end

    expect(response).to redirect_to(connections_path)
  end

  it "asks for the e-mail and the password only, and signs in in the background" do
    get connection_path("zwift")
    expect(response.body).to include(%(id="zwift_password"))
    expect(response.body).not_to include(%(id="retrieval_from_zwift"))
    expect(response.body).to include(ERB::Util.h(I18n.t("settings.connections.zwift.privacy")))

    expect do
      post connection_link_path("zwift"),
           params: { email: "rider@example.test", password: "secret-pass",
                     retrieval: { from: "2026-08-01", to: "2026-08-31" } }
    end.to have_enqueued_job(ImportConnections::Zwift::LinkJob)

    expect(user.import_connections.sole).to have_attributes(provider: "zwift", status: "pending")
    expect(enqueued_jobs.last[:args].to_s).not_to include("secret-pass")
    expect(enqueued_jobs.last[:args].to_s).not_to include("2026-08-01")
    expect(user.workout_import_batches).to be_empty

    get connection_path("zwift")
    expect(response.body).to include(I18n.t("settings.connections.zwift.signing_in"))
  end

  describe "a linked account" do
    let!(:connection) do
      create(:import_connection, :linked, user:, provider: "zwift", external_account_id: "8701091",
                                          external_account_name: "rider@example.test",
                                          token_expires_at: 8.days.from_now,
                                          credentials: { "refresh_token" => "R1", "player_id" => "8701091" })
    end

    it "offers the ordinary retrieval without a password and names the token's end" do
      get connection_path("zwift")

      expect(response.body).to include(ERB::Util.h(I18n.t("settings.connections.valid_until")))
      zone = Time.find_zone(user.time_zone) || Time.zone
      expect(response.body).to include(
        ERB::Util.h(I18n.l(connection.token_expires_at.in_time_zone(zone).to_date, format: :long))
      )
      expect(response.body).not_to include(%(id="zwift_password"))
      expect(response.body).not_to include(%(id="retrieval_sport_zwift"))
      expect(response.body).not_to include(connection_equipment_path("zwift"))
      expect(response.body).to include(I18n.t("settings.connections.unlink.delete_workouts", provider: "Zwift", count: 0))
    end

    it "retrieves a range" do
      expect do
        post connection_retrievals_path("zwift"),
             params: { retrieval: { from: "2026-08-01", to: "2026-08-31" } }
      end.to have_enqueued_job(Workouts::RemoteImportBatchJob)

      expect(connection.import_batches.sole).to have_attributes(source: "zwift", sport: nil)
    end
  end

  it "offers the Zwift panel on the import page" do
    get new_workout_import_path

    expect(response.body).to include("import-source-tab-zwift")
    expect(response.body).to include(I18n.t("workouts.batch_import.sources.zwift.label"))
    expect(response.body).to include("ti-brand-zwift")
  end
end
