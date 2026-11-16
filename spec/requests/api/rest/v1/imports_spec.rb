# frozen_string_literal: true

require "rails_helper"

RSpec.describe "REST API imports (PLAN_API.md §6.3, §8)", type: :request do
  include ActiveJob::TestHelper

  let(:user) { create(:user) }
  let(:headers) { api_headers_for(user, scopes: %w[import]) }
  let(:galibier) { Rails.root.join("spec/fixtures/gpx/galibier.gpx") }

  before { catalog_sport("cycling") }

  def gpx_upload(path = galibier) = Rack::Test::UploadedFile.new(path, "application/gpx+xml")

  def zip_upload
    buffer = Zip::OutputStream.write_buffer do |zip|
      zip.put_next_entry("rides/galibier.gpx")
      zip.write(File.binread(galibier))
      zip.put_next_entry("rides/multi.gpx")
      zip.write(File.binread(Rails.root.join("spec/fixtures/gpx/multi_segment.gpx")))
    end
    file = Tempfile.new([ "rides", ".zip" ], binmode: true)
    file.write(buffer.string)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "application/zip")
  end

  it "accepts files, answers 202 with the batch, and imports them through the ordinary pipeline" do
    post "/api/rest/v1/imports", params: { files: [ gpx_upload, zip_upload ], fallback_sport: "cycling", notes: "From my script" },
                                 headers: headers

    expect(response).to have_http_status(:accepted)
    expect_api_contract
    batch = user.workout_import_batches.sole
    expect(batch).to have_attributes(source: "file", trigger: "api", notes: "From my script")
    expect(response.headers["Location"]).to end_with("/api/rest/v1/imports/#{batch.to_param}")
    expect(response.parsed_body).to include("id" => batch.to_param, "status" => "queued", "trigger" => "api",
                                            "fallback_sport" => "cycling")

    perform_enqueued_jobs(only: Workouts::ImportBatchJob)

    get "/api/rest/v1/imports/#{batch.to_param}", headers: headers
    expect_api_contract
    body = response.parsed_body
    expect(body["status"]).to eq("completed")
    expect(body["counts"]).to include("total" => 3, "imported" => 2, "duplicate" => 1)
    expect(body["entries"].pluck("path")).to eq([ nil, "rides/galibier.gpx", "rides/multi.gpx" ])
    expect(body["entries"].pluck("workout_id").compact).to all(satisfy { user.workouts.find_by_short_id!(it) })
  end

  it "counts as a bulk import past five entries, like the web" do
    post "/api/rest/v1/imports", params: { files: Array.new(6) { gpx_upload }, fallback_sport: "cycling" }, headers: headers
    batch = user.workout_import_batches.sole
    allow(Workouts::Importer).to receive(:new).and_call_original

    perform_enqueued_jobs(only: Workouts::ImportBatchJob)

    expect(Workouts::Importer).to have_received(:new).with(hash_including(bulk: true)).at_least(:once)
    expect(batch.reload.total_entries).to eq(6)
  end

  it "refuses an import without files or fallback sport, with one error per field" do
    post "/api/rest/v1/imports", params: { fallback_sport: "quidditch" }, headers: headers

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body).to include("code" => "validation_failed")
    expect(response.parsed_body["errors"]).to contain_exactly(
      include("field" => "files", "code" => "required"),
      include("field" => "fallback_sport", "code" => "unknown_sport")
    )
    expect(WorkoutImportBatch.count).to eq(0)
  end

  it "answers 429 with a reason past the account's limits (docs/dev/IMPORT-SOURCES.md)" do
    3.times { create(:workout_import_batch, user:, sport: catalog_sport("cycling")) }

    post "/api/rest/v1/imports", params: { files: [ gpx_upload ], fallback_sport: "cycling" }, headers: headers

    expect(response).to have_http_status(:too_many_requests)
    expect(response.parsed_body).to include("code" => "import_limit", "reason" => "too_many_active_imports")
    expect(response.headers["Retry-After"]).to eq("60")
    expect_api_contract
    expect(user.workout_import_batches.count).to eq(3)
  end

  describe "a Strava archive (PLAN_STRAVA_ARCHIVE.md §8)" do
    def archive_upload(filename: "export_42.zip")
      content = strava_archive_zip(
        "activities.csv" => strava_activities_csv([
          { id: 1, name: "Col du Galibier", type: "Ride", filename: "activities/1.gpx" }
        ]),
        "activities/1.gpx" => File.binread(galibier)
      )
      Rack::Test::UploadedFile.new(StringIO.new(content), "application/zip", original_filename: filename)
    end

    it "imports one archive without a fallback sport" do
      post "/api/rest/v1/imports", params: { source: "strava_archive", files: [ archive_upload ] }, headers: headers

      expect(response).to have_http_status(:accepted)
      expect_api_contract
      batch = user.workout_import_batches.sole
      expect(batch).to have_attributes(source: "strava_archive", trigger: "api", sport: nil)
      expect(response.parsed_body).to include("source" => "strava_archive", "fallback_sport" => nil)

      perform_enqueued_jobs(only: Workouts::StravaArchiveImportJob)

      get "/api/rest/v1/imports/#{batch.to_param}", headers: headers
      expect_api_contract
      expect(response.parsed_body["counts"]).to include("total" => 1, "imported" => 1)
      expect(user.workouts.sole.title).to eq("Col du Galibier")
    end

    it "refuses anything but one archive, an unknown source and an unknown fallback" do
      post "/api/rest/v1/imports", params: { source: "strava_archive", files: [ archive_upload, archive_upload ],
                                             fallback_sport: "quidditch" }, headers: headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["errors"]).to contain_exactly(
        include("field" => "files", "code" => "one_archive"),
        include("field" => "fallback_sport", "code" => "unknown_sport")
      )

      post "/api/rest/v1/imports", params: { source: "strava_archive", files: [ gpx_upload ] }, headers: headers
      expect(response.parsed_body["errors"]).to contain_exactly(include("field" => "files", "code" => "not_zip"))

      post "/api/rest/v1/imports", params: { source: "garmin", files: [ gpx_upload ] }, headers: headers
      expect(response.parsed_body["errors"]).to contain_exactly(include("field" => "source", "code" => "unknown_source"))
      expect(WorkoutImportBatch.count).to eq(0)
    end
  end

  it "needs the import scope to send files, and import or read to follow them" do
    batch = create(:workout_import_batch, user:, sport: catalog_sport("cycling"))
    read_only = api_headers_for(user, scopes: %w[read])

    post "/api/rest/v1/imports", params: { files: [ gpx_upload ], fallback_sport: "cycling" }, headers: read_only
    expect(response.parsed_body["code"]).to eq("insufficient_scope")

    get "/api/rest/v1/imports/#{batch.to_param}", headers: read_only
    expect(response).to have_http_status(:ok)
  end

  it "lists the account's imports newest first, never another account's" do
    older = create(:workout_import_batch, user:, sport: catalog_sport("cycling"), created_at: 2.days.ago)
    newer = create(:workout_import_batch, user:, sport: catalog_sport("cycling"), created_at: 1.day.ago)
    others = create(:workout_import_batch, sport: catalog_sport("cycling"))

    get "/api/rest/v1/imports", headers: headers

    expect(response.parsed_body["data"].pluck("id")).to eq([ newer.to_param, older.to_param ])
    expect(response.parsed_body["data"].first).not_to have_key("entries")
    expect_api_contract

    get "/api/rest/v1/imports/#{others.to_param}", headers: headers
    expect(response).to have_http_status(:not_found)
  end

  describe "DELETE /imports/:id" do
    it "asks a running import to stop" do
      batch = create(:workout_import_batch, user:, sport: catalog_sport("cycling"), status: "processing")

      delete "/api/rest/v1/imports/#{batch.to_param}", headers: headers

      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body["cancellation_requested"]).to be(true)
      expect(batch.reload).to be_cancellation_requested
      expect_api_contract
    end

    it "answers 409 for a finished import" do
      batch = create(:workout_import_batch, user:, sport: catalog_sport("cycling"), status: "completed")

      delete "/api/rest/v1/imports/#{batch.to_param}", headers: headers

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body["code"]).to eq("import_finished")
      expect_api_contract
    end
  end

  describe "Idempotency-Key" do
    it "replays the first response to a retry instead of importing twice" do
      keyed = headers.merge("Idempotency-Key" => "upload-1")

      post "/api/rest/v1/imports", params: { files: [ gpx_upload ], fallback_sport: "cycling" }, headers: keyed
      first = response.parsed_body
      post "/api/rest/v1/imports", params: { files: [ gpx_upload ], fallback_sport: "cycling" }, headers: keyed

      expect(response).to have_http_status(:accepted)
      expect(response.headers["Idempotency-Replayed"]).to eq("true")
      expect(response.headers["Location"]).to end_with(first["id"])
      expect(response.parsed_body).to eq(first)
      expect(WorkoutImportBatch.count).to eq(1)
      expect_api_contract
    end

    it "refuses the same key with a different request" do
      keyed = headers.merge("Idempotency-Key" => "upload-2")
      post "/api/rest/v1/imports", params: { files: [ gpx_upload ], fallback_sport: "cycling" }, headers: keyed

      post "/api/rest/v1/imports", params: { files: [ gpx_upload ], fallback_sport: "running" }, headers: keyed

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["code"]).to eq("idempotency_key_reused")
      expect(WorkoutImportBatch.count).to eq(1)
    end

    it "refuses a retry while the first request is still running" do
      token = ApiToken.authenticate(headers["Authorization"].delete_prefix("Bearer "))
      ApiIdempotencyKey.create!(api_token: token, key: "upload-3", request_digest: "0" * 64, expires_at: 1.hour.from_now)
      allow_any_instance_of(Api::Rest::V1::ImportsController).to receive(:request_fingerprint).and_return("0" * 64) # rubocop:disable RSpec/AnyInstance

      post "/api/rest/v1/imports", params: { files: [ gpx_upload ], fallback_sport: "cycling" },
                                   headers: headers.merge("Idempotency-Key" => "upload-3")

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body["code"]).to eq("idempotency_key_in_progress")
    end

    it "keeps keys apart per token, and forgets them after a day" do
      keyed = headers.merge("Idempotency-Key" => "upload-4")
      post "/api/rest/v1/imports", params: { files: [ gpx_upload ], fallback_sport: "cycling" }, headers: keyed
      ApiIdempotencyKey.update_all(expires_at: 1.second.ago)

      post "/api/rest/v1/imports", params: { files: [ gpx_upload ], fallback_sport: "cycling" }, headers: keyed

      expect(response.headers["Idempotency-Replayed"]).to be_nil
      expect(WorkoutImportBatch.count).to eq(2)
    end

    it "does not keep a refusal for a missing scope" do
      read_only = api_headers_for(user, scopes: %w[read]).merge("Idempotency-Key" => "upload-5")

      post "/api/rest/v1/imports", params: { files: [ gpx_upload ], fallback_sport: "cycling" }, headers: read_only

      expect(response).to have_http_status(:forbidden)
      expect(ApiIdempotencyKey.count).to eq(0)
    end
  end

  it "shows the API trigger on the web import page" do
    batch = create(:workout_import_batch, user:, sport: catalog_sport("cycling"), trigger: "api")
    sign_in_as(user)

    get workout_import_path(batch)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("workouts.batch_import.show.triggers.api", locale: :fr))
  end
end
