# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Strava archive imports" do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }

  def sign_in_user
    post session_path, params: { email_address: user.email_address, password: "allure-test-password" }
  end

  def upload(content, filename: "export_42.zip")
    Rack::Test::UploadedFile.new(StringIO.new(content), "application/zip", original_filename: filename)
  end

  def archive = strava_archive_zip("activities.csv" => strava_activities_csv([ { id: 1, name: "Sortie" } ]))

  it "requires authentication" do
    post strava_archive_imports_path

    expect(response).to redirect_to(new_session_path)
  end

  it "renders the Strava archive panel with its own submit" do
    sign_in_user

    get new_workout_import_path

    expect(response.body).to include('data-source="strava_archive"', 'data-kind="archive"')
    expect(response.body).to include(%(formaction="#{strava_archive_imports_path}"))
    expect(response.body).to include("Archive Strava")
  end

  it "creates a Strava archive batch and enqueues its job" do
    sign_in_user
    hiking = catalog_sport("hiking")

    expect do
      post strava_archive_imports_path, params: {
        workout_import_batch: { strava_archive: upload(archive), strava_sport_id: hiking.id,
                                sport_id: "", source_files: [ "" ] }
      }
    end.to have_enqueued_job(Workouts::StravaArchiveImportJob)

    batch = user.workout_import_batches.last
    expect(batch).to have_attributes(source: "strava_archive", trigger: "manual", sport: hiking)
    expect(batch.source_files.first.filename.to_s).to eq("export_42.zip")
    expect(response).to redirect_to(workout_import_path(batch))
  end

  it "needs no fallback sport" do
    sign_in_user

    post strava_archive_imports_path, params: { workout_import_batch: { strava_archive: upload(archive) } }

    expect(user.workout_import_batches.last).to have_attributes(source: "strava_archive", sport: nil)
  end

  it "returns to the panel without an archive or with another file" do
    sign_in_user

    expect do
      post strava_archive_imports_path, params: { workout_import_batch: { strava_sport_id: "" } }
    end.not_to change(WorkoutImportBatch, :count)
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include('data-import-source-initial-value="strava_archive"')
    expect(response.body).to include(I18n.t("workouts.batch_import.errors.missing_strava_archive"))

    post strava_archive_imports_path,
         params: { workout_import_batch: { strava_archive: upload("<gpx/>", filename: "ride.gpx") } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include(I18n.t("workouts.batch_import.errors.strava_archive_not_zip"))
  end

  it "shows the archive's activities on the batch page" do
    sign_in_user
    batch = create(:workout_import_batch, user:, sport: nil, source: "strava_archive", status: "processing")
    create(:workout_import_entry, batch:, source_name: "Col du Galibier", source_path: "activities/9001.fit.gz",
                                  status: "skipped", skip_reason: "no_file",
                                  metadata: { "created_equipment" => "Canyon", "photos" => 3, "photos_missing" => 2, "photos_refused" => 1 })

    get workout_import_path(batch)

    expect(response.body).to include("Archive Strava", "Col du Galibier", "activities/9001.fit.gz")
    expect(response.body).to include("Équipement créé : Canyon")
    expect(response.body).to include("3 photos jointes · 2 photos absentes de l’archive · 1 photo refusée")
  end

  it "refuses a second archive while one is waiting (docs/dev/IMPORT-SOURCES.md)" do
    create(:workout_import_batch, user:, sport: nil, source: "strava_archive", status: "processing")
    sign_in_user

    expect do
      post strava_archive_imports_path, params: { workout_import_batch: { strava_archive: upload(archive) } }
    end.not_to change(ActiveStorage::Blob, :count)

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Une archive Strava est déjà en cours d&#39;import")
    expect(user.workout_import_batches.count).to eq(1)
  end
end
