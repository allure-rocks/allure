# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Remote import sources on the import pages" do
  let(:user) { create(:user) }
  let(:connection) { create(:import_connection, :linked, user:) }

  before { sign_in_as(user) }

  it "offers the Garmin Connect panel only while the operator enables it" do
    with_remote_import_enabled do
      get new_workout_import_path

      expect(response.body).to include(%(data-source="garmin_connect" data-kind="remote"))
      expect(response.body).to include(ERB::Util.html_escape(
        I18n.t("workouts.batch_import.remote.not_linked", provider: "Garmin Connect")
      ))
    end

    with_remote_import_enabled(enabled: false) do
      get new_workout_import_path

      expect(response.body).not_to include(%(data-source="garmin_connect"))
    end
  end

  it "renders a remote batch with its source, its pause and its skipped entries" do
    batch = create(:workout_import_batch, user:, sport: nil, source: "garmin_connect", import_connection: connection,
                                          status: "processing", paused_until: 10.minutes.from_now)
    create(:workout_import_entry, batch:, status: "skipped", skip_reason: "no_geometry")
    batch.refresh_progress!

    get workout_import_path(batch)

    expect(response.body).to include("Garmin Connect")
    expect(response.body).to include(I18n.t("workouts.batch_import.entries.skip_reasons.no_geometry"))
    expect(response.body).to include(I18n.t("workouts.batch_import.status.skipped", count: 1))
    expect(response.body).to include(I18n.t("workouts.batch_import.entries.labels.skipped"))
    expect(response.body).to include("ti-hourglass")
  end
end
