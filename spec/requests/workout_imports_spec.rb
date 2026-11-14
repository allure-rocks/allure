# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Workout batch imports" do
  let(:user) { create(:user) }
  let(:sport) { create(:sport) }

  def sign_in_user
    post session_path, params: { email_address: user.email_address, password: "allure-test-password" }
  end

  it "requires authentication" do
    get new_workout_import_path

    expect(response).to redirect_to(new_session_path)
  end

  it "excludes the import form from Turbo snapshots with stale CSRF tokens" do
    sign_in_user

    get new_workout_import_path

    expect(response.parsed_body.at_css('head meta[name="turbo-cache-control"]')["content"]).to eq("no-cache")
  end

  it "does not expose legacy visibility selectors" do
    sign_in_user

    get new_workout_import_path

    expect(response.body).not_to include("workout_import_batch_workout_visibility")
    expect(response.body).not_to include("visibility#capChildren")
  end

  it "advertises supported track sources in the batch form" do
    sign_in_user

    get new_workout_import_path

    expect(response.body).to include(".tcx", ".kmz", "Fichiers GPX/FIT/TCX/KML ou archives")
    expect(response.body).to include("des fichiers .gpx, .fit, .tcx")
  end

  it "renders a source picker with the file and iGPSPORT device panels" do
    sign_in_user

    get new_workout_import_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-controller="import-source"')
    expect(response.body).to include('data-source="file"')
    expect(response.body).to include('data-source="igpsport_device"')
    expect(response.body).to include('data-controller="igpsport-device"')
    expect(response.body).not_to include("iGPSPORT (BSC)")
    expect(response.body).to include("Chrome ou Edge")
    expect(response.body).to include("Connecter le compteur")
    expect(Nokogiri::HTML(response.body).at_css('[data-igpsport-device-target="untested"]')["hidden"]).not_to be_nil
  end

  it "serializes the device messages as a JSON Stimulus value" do
    sign_in_user

    get new_workout_import_path

    node = Nokogiri::HTML(response.body).at_css("[data-igpsport-device-messages-value]")
    messages = JSON.parse(node["data-igpsport-device-messages-value"])

    expect(messages).to include(
      "connecting", "downloading", "handoff_failed", "unsupported_model",
      "empty", "summary", "select_all", "clear_all"
    )
    expect(messages["downloading"]).to include("%{current}", "%{total}", "%{percent}")
    expect(messages["unsupported_model"]).to include("%{name}")
    expect(node["data-igpsport-device-native-value"]).to eq("false")
    expect(node["data-controller"].split).not_to include("bridge--igpsport")
  end

  describe "iOS companion" do
    let(:native_agent) do
      "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 " \
        "(KHTML, like Gecko) Mobile/15E148 Allure iOS/0.2.0 Hotwire Native iOS; " \
        "Turbo Native iOS; bridge-components: [topbar igpsport]"
    end

    it "lends the app's Bluetooth to the device panel when it registers the bridge" do
      sign_in_user

      get new_workout_import_path, headers: { "User-Agent" => native_agent }

      node = Nokogiri::HTML(response.body).at_css("[data-igpsport-device-messages-value]")
      expect(node["data-controller"].split).to include("igpsport-device", "bridge--igpsport")
      expect(node["data-igpsport-device-native-value"]).to eq("true")
      expect(response.body).not_to include("Chrome ou Edge")
    end

    it "asks an older app without the bridge to update" do
      sign_in_user

      get new_workout_import_path, headers: { "User-Agent" => native_agent.sub("[topbar igpsport]", "[topbar]") }

      node = Nokogiri::HTML(response.body).at_css("[data-igpsport-device-messages-value]")
      expect(node["data-controller"].split).not_to include("bridge--igpsport")
      expect(node["data-igpsport-device-native-value"]).to eq("false")
      expect(response.body).to include("Mettez à jour l’application Allure")
      expect(response.body).not_to include("Chrome ou Edge")
    end

    it "hands share-sheet files to the file panel when the app registers the bridge" do
      sign_in_user

      get new_workout_import_path, headers: { "User-Agent" => native_agent.sub("igpsport]", "igpsport shared-files]") }

      node = Nokogiri::HTML(response.body).at_css("[data-bridge--shared-files-received-value]")
      expect(node["data-controller"].split).to include("bridge--shared-files")
      expect(node["data-bridge--shared-files-received-value"]).to include("%{names}")
      expect(node["data-bridge--shared-files-failed-value"]).to be_present
      expect(response.body).to include('data-bridge--shared-files-target="status"')
    end

    it "leaves the file panel plain for an app without the shared-files bridge" do
      sign_in_user

      get new_workout_import_path, headers: { "User-Agent" => native_agent }

      expect(response.body).not_to include("bridge--shared-files")
    end
  end

  it "queues selected sources and stores them on the batch" do
    sign_in_user
    files = [
      fixture_file_upload("spec/fixtures/gpx/galibier.gpx", "application/gpx+xml"),
      fixture_file_upload("spec/fixtures/gpx/multi_segment.gpx", "application/gpx+xml")
    ]
    allow(Workouts::ImportBatchJob).to receive(:perform_later).and_wrap_original do |method, batch|
      expect(batch.source_files.attachments.size).to eq(2)
      method.call(batch)
    end

    expect do
      expect do
        post workout_imports_path,
             params: {
               workout_import_batch: {
                 source_files: files,
                 sport_id: sport.id,
                 notes: "Imported archive"
               }
             }
      end.to have_enqueued_job(Workouts::ImportBatchJob)
    end.to change(WorkoutImportBatch, :count).by(1)

    expect(response).to redirect_to(workout_import_path(WorkoutImportBatch.last))
    expect(WorkoutImportBatch.last.source_files.attachments.size).to eq(2)
  end

  it "rejects a batch without files" do
    sign_in_user

    post workout_imports_path, params: { workout_import_batch: { sport_id: sport.id } }

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("doit contenir au moins un fichier")
  end

  it "renders the shared options card with the single-file title, gear and commute" do
    create(:equipment, user:, label: "Road bike")
    sign_in_user

    get new_workout_import_path

    page = Nokogiri::HTML(response.body)
    expect(page.at_css('[data-import-source-target="single"]')["hidden"]).not_to be_nil
    expect(response.body).to include("workout_import_batch[equipment_ids][]", "Road bike", "workout_import_batch[commute]")
    expect(response.body).to include(ERB::Util.html_escape(I18n.t("workouts.batch_import.form.title_hint")))
    expect(response.body).to include(ERB::Util.html_escape(I18n.t("workouts.batch_import.form.equipment_hint")))
    expect(response.body).to include(ERB::Util.html_escape(I18n.t("workouts.batch_import.form.commute_hint")))
  end

  it "stores the options card on the batch" do
    gear = create(:equipment, user:)
    sign_in_user

    post workout_imports_path, params: {
      workout_import_batch: {
        source_files: [ fixture_file_upload("spec/fixtures/gpx/galibier.gpx", "application/gpx+xml") ],
        sport_id: sport.id,
        title: "Morning hike",
        commute: "1",
        equipment_ids: [ gear.id.to_s ]
      }
    }

    batch = WorkoutImportBatch.last
    expect(batch).to have_attributes(title: "Morning hike", commute: true)
    expect(batch.equipment_ids).to eq([ gear.id ])
  end

  it "ignores another account's equipment" do
    foreign = create(:equipment)
    sign_in_user

    post workout_imports_path, params: {
      workout_import_batch: {
        source_files: [ fixture_file_upload("spec/fixtures/gpx/galibier.gpx", "application/gpx+xml") ],
        sport_id: sport.id,
        equipment_ids: [ foreign.id.to_s ]
      }
    }

    expect(WorkoutImportBatch.last.equipment_ids).to be_empty
  end

  it "does not expose another user's batch" do
    other = create(:user)
    batch = create(:workout_import_batch, user: other, sport:)
    sign_in_user

    get workout_import_path(batch)

    expect(response).to have_http_status(:not_found)
  end

  it "shows the selected type, fallback marker, and distance for imported entries" do
    fallback_sport = catalog_sport("cycling")
    detected_sport = catalog_sport("running")
    batch = create(:workout_import_batch, user:, sport: fallback_sport)
    detected_workout = create(:workout, user:, sport: detected_sport, distance: 2_500)
    fallback_workout = create(:workout, user:, sport: fallback_sport, distance: 12_345)
    create(:workout_import_entry, batch:, workout: detected_workout, status: "imported", position: 0, sport_source: "detected")
    create(:workout_import_entry, batch:, workout: fallback_workout, status: "imported", position: 1, sport_source: "fallback")
    sign_in_user

    get workout_import_path(batch)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Course à pied", "Vélo", "2,5 km", "12,35 km")
    expect(response.body.scan("Sport de secours").length).to eq(1)
  end

  it "requests cancellation only for the current user's active batch" do
    batch = create(:workout_import_batch, user:, sport:)
    sign_in_user

    post cancel_workout_import_path(batch)

    expect(response).to redirect_to(workout_import_path(batch))
    expect(batch.reload.cancellation_requested_at).to be_present
  end

  it "announces status transitions through a persistent live region" do
    batch = create(:workout_import_batch, user:, sport:)
    sign_in_user

    get workout_import_path(batch)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('role="status"', 'data-batch-import-target="announcer"')
    expect(response.body).to include("data-status-text")
  end

  it "renders the frozen total, waiting files, and the current file while polling" do
    batch = create(
      :workout_import_batch,
      user:,
      sport:,
      status: "processing",
      total_entries: 4,
      processed_entries: 1,
      imported_entries: 1
    )
    create(:workout_import_entry, batch:, status: "imported", position: 0, source_key: "1:0")
    create(:workout_import_entry, batch:, status: "processing", position: 1, source_key: "1:1", source_name: "ride.gpx")
    create(:workout_import_entry, batch:, status: "queued", position: 2, source_key: "1:2", source_name: "walk.gpx")
    create(:workout_import_entry, batch:, status: "queued", position: 3, source_key: "1:3", source_name: "hike.gpx")
    sign_in_user

    get status_workout_import_path(batch)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('aria-valuenow="25"')
    expect(response.body).to include("1 fichier(s) traité(s) sur 4")
    expect(response.body).to include("3 fichiers en attente")
    expect(response.body).to include("Import en cours : ride.gpx")
    expect(response.body).to include("En attente")
    expect(response.body).not_to include("data-batch-import-notice")
  end

  it "offers the activity list and a completion notice once a batch is terminal" do
    batch = create(
      :workout_import_batch,
      user:,
      sport:,
      status: "completed",
      total_entries: 2,
      processed_entries: 2,
      imported_entries: 2
    )
    sign_in_user

    get workout_import_path(batch)

    expect(response.body).to include("Voir les activités")
    expect(response.body).to include("data-batch-import-notice")
    expect(response.body).to include('data-notice-title="Import terminé"')
    expect(response.body).to include('data-notice-level="success"')
  end

  describe "admission (PLAN_IMPORT_SOURCES.md §3.2)" do
    def post_gpx
      post workout_imports_path, params: {
        workout_import_batch: {
          source_files: [ fixture_file_upload("spec/fixtures/gpx/galibier.gpx", "application/gpx+xml") ],
          sport_id: sport.id
        }
      }
    end

    it "records the upload's size on the batch" do
      sign_in_user

      post_gpx

      expect(user.workout_import_batches.last.source_bytes).to eq(File.size("spec/fixtures/gpx/galibier.gpx"))
    end

    it "refuses a fourth import while three are waiting, storing nothing" do
      3.times { create(:workout_import_batch, user:, sport:) }
      sign_in_user

      expect { post_gpx }.not_to change(ActiveStorage::Blob, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("3 imports sont déjà en cours")
      expect(user.workout_import_batches.count).to eq(3)
    end

    it "refuses an upload past the day's budget" do
      create(:workout_import_batch, user:, sport:, status: "completed",
                                    source_bytes: Workouts::ImportAdmission::DAILY_UPLOAD_BYTES)
      sign_in_user

      post_gpx

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Vous avez envoyé 6 GB ces dernières 24 heures")
    end

    it "answers too many requests from one account" do
      counts = Hash.new(0)
      allow(WorkoutImportsController.cache_store).to receive(:increment) do |key, amount = 1, **|
        counts[key] += amount
      end
      sign_in_user
      post_gpx
      counts.transform_values! { 20 }

      post_gpx

      expect(response).to have_http_status(:too_many_requests)
      expect(response.body).to include("Trop d&#39;imports en peu de temps")
    end
  end
end
