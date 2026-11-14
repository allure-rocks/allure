# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Connected services: EXR" do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }

  around { |example| with_remote_import_enabled("exr") { example.run } }

  before { sign_in_as(user) }

  it "starts a background sign-in holding the password only in the encrypted row" do
    get connection_path("exr")
    expect(response.body).to include(%(id="exr_password"))

    expect { post connection_link_path("exr"), params: { email: "rower@example.test", password: "secret-pass" } }
      .to have_enqueued_job(ImportConnections::Exr::LinkJob)

    expect(user.import_connections.sole).to have_attributes(provider: "exr", status: "pending")
    expect(enqueued_jobs.last[:args].to_s).not_to include("secret-pass")

    get connection_path("exr")
    expect(response.body).to include(I18n.t("settings.connections.exr.signing_in"))
  end

  describe "a linked account" do
    let!(:connection) do
      create(:import_connection, :linked, user:, provider: "exr", external_account_id: nil,
                                          external_account_name: "rower@example.test", token_expires_at: Time.utc(2031, 10, 8),
                                          credentials: { "remember_cookie_name" => "remember_web_abc", "remember_cookie" => "R1" })
    end

    it "offers neither equipment nor a fallback sport, and names the cookie's end" do
      get connection_path("exr")

      expect(response.body).to include(ERB::Util.h(I18n.t("settings.connections.valid_until")))
      expect(response.body).not_to include(connection_equipment_path("exr"))
      expect(response.body).not_to include(%(id="retrieval_sport_exr"))
      expect(response.body).to include(I18n.t("settings.connections.unlink.delete_workouts", provider: "EXR", count: 0))
    end

    it "retrieves a range without a sport and refuses equipment" do
      expect do
        post connection_retrievals_path("exr"),
             params: { retrieval: { from: "2026-09-01", to: "2026-09-30", sport_id: catalog_sport("cycling").id } }
      end.to have_enqueued_job(Workouts::RemoteImportBatchJob)
      expect(connection.import_batches.sole).to have_attributes(source: "exr", sport: nil)

      post connection_equipment_path("exr")
      expect(response).to have_http_status(:not_found)
    end
  end
end
