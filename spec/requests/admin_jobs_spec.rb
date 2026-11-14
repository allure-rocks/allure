# frozen_string_literal: true

require "rails_helper"

# The live background-job panel and its recovery controls (PLAN_ADMIN.md §4.2).
RSpec.describe "Admin jobs" do
  let(:operator) { create(:user, :with_totp, username: "operator") }
  let(:member) { create(:user) }

  around do |example|
    previous = ENV["INSTANCE_OPERATOR_USERNAME"]
    ENV["INSTANCE_OPERATOR_USERNAME"] = "operator"
    example.run
  ensure
    previous.nil? ? ENV.delete("INSTANCE_OPERATOR_USERNAME") : ENV["INSTANCE_OPERATOR_USERNAME"] = previous
  end

  before { clear_solid_queue! }

  describe "authorization" do
    it "redirects an anonymous visitor" do
      get admin_jobs_path

      expect(response).to redirect_to(new_session_path)
    end

    it "answers 404 to a member, and performs nothing" do
      job = create_failed_job
      sign_in_as(member)

      get admin_jobs_path
      expect(response).to have_http_status(:not_found)

      post admin_job_retry_path(SolidQueue::FailedExecution.first)
      expect(response).to have_http_status(:not_found)
      expect(SolidQueue::FailedExecution.where(job:)).to exist

      post admin_jobs_rebuild_path
      expect(response).to have_http_status(:not_found)
      expect(AdminEvent.count).to eq(0)
    end
  end

  describe "show" do
    before { sign_in_as(operator) }

    it "renders queue depths, processes, and failures" do
      create_failed_job(message: "the sky fell")
      create_ready_job
      SolidQueue::Pause.create!(queue_name: "default")

      get admin_jobs_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("admin.jobs.title"))
      expect(response.body).to include("the sky fell")
      expect(response.body).to include("Workouts::ReanalyzeJob")
      expect(response.body).to include(I18n.t("admin.jobs.queues.paused"))
    end

    it "serves the live fragment without a layout and without caching" do
      get admin_jobs_path, headers: { "Turbo-Frame" => "admin-jobs-live" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("data-live-jobs")
      expect(response.body).not_to include("<html")
      expect(response.headers["Cache-Control"]).to eq("no-store")
    end

    it "shows the queue command recurring tasks actually land on" do
      SolidQueue::RecurringTask.create!(key: "cleanup", schedule: "every hour", command: "true")

      get admin_jobs_path

      expect(response.body).to include("solid_queue_recurring")
    end
  end

  describe "failed job recovery" do
    before { sign_in_as(operator) }

    it "retries one failure" do
      job = create_failed_job
      failure = SolidQueue::FailedExecution.first

      post admin_job_retry_path(failure)

      expect(response).to redirect_to(admin_jobs_path(anchor: "failed"))
      expect(SolidQueue::FailedExecution.where(job:)).not_to exist
      expect(SolidQueue::ReadyExecution.where(job:)).to exist
      expect(AdminEvent.last).to have_attributes(action: "job_retried", user: operator)
    end

    it "discards one failure and its job" do
      job = create_failed_job

      post admin_job_discard_path(SolidQueue::FailedExecution.first)

      expect(response).to redirect_to(admin_jobs_path(anchor: "failed"))
      expect(SolidQueue::FailedExecution.count).to eq(0)
      expect(SolidQueue::Job.where(id: job.id)).not_to exist
      expect(AdminEvent.last).to have_attributes(action: "job_discarded", user: operator)
    end

    it "retries every failure" do
      2.times { create_failed_job }

      post admin_jobs_retry_all_path

      expect(SolidQueue::FailedExecution.count).to eq(0)
      expect(SolidQueue::ReadyExecution.count).to eq(2)
      expect(AdminEvent.last).to have_attributes(action: "jobs_retried")
      expect(AdminEvent.last.metadata["count"]).to eq(2)
    end

    it "discards every failure" do
      2.times { create_failed_job }

      post admin_jobs_discard_all_path

      expect(SolidQueue::FailedExecution.count).to eq(0)
      expect(SolidQueue::Job.count).to eq(0)
      expect(AdminEvent.last).to have_attributes(action: "jobs_discarded")
      expect(AdminEvent.last.metadata["count"]).to eq(2)
    end
  end

  describe "queue pause and resume" do
    before { sign_in_as(operator) }

    it "pauses and resumes a known queue" do
      create_ready_job(queue_name: "route_images")

      post admin_queue_pause_path("route_images")
      expect(SolidQueue::Pause.exists?(queue_name: "route_images")).to be(true)
      expect(AdminEvent.last).to have_attributes(action: "queue_paused")
      expect(AdminEvent.last.metadata["queue"]).to eq("route_images")

      post admin_queue_resume_path("route_images")
      expect(SolidQueue::Pause.exists?(queue_name: "route_images")).to be(false)
      expect(AdminEvent.last).to have_attributes(action: "queue_resumed")
    end

    it "rejects an unknown queue" do
      post admin_queue_pause_path("nonsense")

      expect(response).to have_http_status(:not_found)
      expect(AdminEvent.count).to eq(0)
    end
  end

  describe "rebuild sweep" do
    before do
      sign_in_as(operator)
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    end

    def with_original_file(workout)
      workout.original_file.attach(io: StringIO.new("bytes"), filename: "ride.fit",
                                   content_type: "application/octet-stream")
      workout
    end

    it "enqueues the sweep for workouts stale in either generation and audits the count" do
      with_original_file(create(:workout, user: member, analysis_version: Allure::Gpx::Analyzer::VERSION - 1))
      with_original_file(create(:workout, user: member, import_detection_version: 0))
      with_original_file(create(:workout, user: member))
      create(:workout, user: member, import_detection_version: 0)

      post admin_jobs_rebuild_path

      expect(response).to redirect_to(admin_jobs_path)
      expect(Workouts::BackfillRebuildJob).to have_been_enqueued
      expect(AdminEvent.last).to have_attributes(action: "workouts_rebuild_enqueued", user: operator)
      expect(AdminEvent.last.metadata["count"]).to eq(2)
    end

    it "does not enqueue when every workout is current" do
      with_original_file(create(:workout, user: member))

      post admin_jobs_rebuild_path

      expect(response).to redirect_to(admin_jobs_path)
      expect(Workouts::BackfillRebuildJob).not_to have_been_enqueued
      expect(AdminEvent.count).to eq(0)
    end

    it "shows the outdated count and the rebuild action" do
      with_original_file(create(:workout, user: member, analysis_version: Allure::Gpx::Analyzer::VERSION - 1))

      get admin_jobs_path

      expect(response.body).to include(I18n.t("admin.jobs.rebuild.action"))
      expect(response.body).to include(ERB::Util.html_escape(I18n.t("admin.jobs.rebuild.outdated", count: 1)))
    end

    it "enqueues the elevation backfill for pending workouts and audits the count" do
      with_env("ELEVATION_BASE_URL" => "https://elevation.test") do
        create(:workout, user: create(:user, elevation_enrichment_enabled: true),
                         sport: catalog_sport("running"), min_elevation: nil, max_elevation: nil)

        post admin_jobs_backfill_elevation_path

        expect(response).to redirect_to(admin_jobs_path)
        expect(Workouts::BackfillElevationJob).to have_been_enqueued
        expect(AdminEvent.last).to have_attributes(action: "elevation_backfill_enqueued", user: operator)
        expect(AdminEvent.last.metadata["count"]).to eq(1)
      end
    end

    it "does not enqueue the elevation backfill without a provider" do
      with_env("ELEVATION_BASE_URL" => nil) do
        post admin_jobs_backfill_elevation_path

        expect(Workouts::BackfillElevationJob).not_to have_been_enqueued
        expect(AdminEvent.count).to eq(0)
      end
    end

    it "shows the elevation action when the provider is configured" do
      with_env("ELEVATION_BASE_URL" => "https://elevation.test") do
        create(:workout, user: create(:user, elevation_enrichment_enabled: true),
                         sport: catalog_sport("running"), min_elevation: nil, max_elevation: nil)

        get admin_jobs_path

        expect(response.body).to include(I18n.t("admin.jobs.elevation.action"))
      end
    end
  end

  describe "weather backfill", :weather do
    before { sign_in_as(operator) }

    it "schedules the weather of consenting accounts and audits the count" do
      weather_workout(user: create(:user, weather_enrichment_enabled: true))
      weather_workout(user: member)

      get admin_jobs_path
      expect(response.body).to include(I18n.t("admin.jobs.weather.action"))

      post admin_jobs_backfill_weather_path

      expect(response).to redirect_to(admin_jobs_path)
      expect(Workouts::BackfillWeatherJob).to have_been_enqueued
      expect(AdminEvent.last).to have_attributes(action: "weather_backfill_enqueued", user: operator)
      expect(AdminEvent.last.metadata["count"]).to eq(1)
    end

    it "does nothing while the feature is off" do
      weather_workout(user: create(:user, weather_enrichment_enabled: true))

      with_env("WEATHER_ENABLED" => nil) do
        post admin_jobs_backfill_weather_path

        expect(Workouts::BackfillWeatherJob).not_to have_been_enqueued
        expect(AdminEvent.count).to eq(0)
      end
    end
  end

  describe "places backfill" do
    before do
      sign_in_as(operator)
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    end

    it "enqueues the places backfill for stale selections and audits the count" do
      with_env("GEOCODING_BASE_URL" => "https://geocoding.test") do
        create(:workout_toponymy)

        post admin_jobs_backfill_places_path

        expect(response).to redirect_to(admin_jobs_path)
        expect(Workouts::BackfillPlacesJob).to have_been_enqueued
        expect(AdminEvent.last).to have_attributes(action: "places_backfill_enqueued", user: operator)
        expect(AdminEvent.last.metadata["count"]).to eq(1)
      end
    end

    it "does not enqueue the places backfill without a provider" do
      with_env("GEOCODING_BASE_URL" => nil) do
        create(:workout_toponymy)

        post admin_jobs_backfill_places_path

        expect(Workouts::BackfillPlacesJob).not_to have_been_enqueued
        expect(AdminEvent.count).to eq(0)
      end
    end

    it "shows the places action when the provider is configured" do
      with_env("GEOCODING_BASE_URL" => "https://geocoding.test") do
        create(:workout_toponymy)

        get admin_jobs_path

        expect(response.body).to include(I18n.t("admin.jobs.places.action"))
      end
    end
  end

  describe "toponymy backfill" do
    before do
      sign_in_as(operator)
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    end

    it "enqueues the geocoding sweep for outdated toponymies and audits the count" do
      with_env("GEOCODING_BASE_URL" => "https://geocoding.test") do
        create(:workout_toponymy, algorithm_version: Workouts::ToponymyEnricher::ALGORITHM_VERSION - 1)
        count = Workouts::BackfillToponymyJob.pending_scope.count

        get admin_jobs_path
        expect(response.body).to include(I18n.t("admin.jobs.toponymy.action"))

        post admin_jobs_backfill_toponymy_path

        expect(response).to redirect_to(admin_jobs_path)
        expect(Workouts::BackfillToponymyJob).to have_been_enqueued
        expect(AdminEvent.last).to have_attributes(action: "toponymy_backfill_enqueued", user: operator)
        expect(AdminEvent.last.metadata["count"]).to eq(count)
      end
    end

    it "does not enqueue the sweep without a provider" do
      with_env("GEOCODING_BASE_URL" => nil) do
        create(:workout_toponymy, algorithm_version: Workouts::ToponymyEnricher::ALGORITHM_VERSION - 1)

        post admin_jobs_backfill_toponymy_path

        expect(Workouts::BackfillToponymyJob).not_to have_been_enqueued
        expect(AdminEvent.count).to eq(0)
      end
    end
  end

  describe "route image backfill" do
    before do
      sign_in_as(operator)
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    end

    it "enqueues the sweep for missing or stale images and audits the count" do
      create(:workout, user: member, route_image_version: 0)
      create(:workout, user: member, route_image_version: Workouts::RouteImage::VERSION)

      post admin_jobs_backfill_route_images_path

      expect(response).to redirect_to(admin_jobs_path)
      expect(Workouts::BackfillRouteImagesJob).to have_been_enqueued
      expect(AdminEvent.last).to have_attributes(action: "route_images_backfill_enqueued", user: operator)
      expect(AdminEvent.last.metadata["count"]).to eq(1)
    end

    it "does not enqueue when every image is current" do
      create(:workout, user: member, route_image_version: Workouts::RouteImage::VERSION)

      post admin_jobs_backfill_route_images_path

      expect(Workouts::BackfillRouteImagesJob).not_to have_been_enqueued
      expect(AdminEvent.count).to eq(0)
    end

    it "shows the route image action" do
      create(:workout, user: member, route_image_version: 0)

      get admin_jobs_path

      expect(response.body).to include(I18n.t("admin.jobs.route_images.action"))
    end
  end

  describe "segment route image backfill" do
    before do
      sign_in_as(operator)
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    end

    it "enqueues the sweep for missing or stale images and audits the count" do
      create(:segment, user: member, route_image_version: 0)
      create(:segment, user: member, route_image_version: Segments::RouteImage::VERSION)

      post admin_jobs_backfill_segment_route_images_path

      expect(response).to redirect_to(admin_jobs_path)
      expect(Segments::BackfillRouteImagesJob).to have_been_enqueued
      expect(AdminEvent.last).to have_attributes(action: "segment_route_images_backfill_enqueued", user: operator)
      expect(AdminEvent.last.metadata["count"]).to eq(1)
    end

    it "does not enqueue when every image is current" do
      create(:segment, user: member, route_image_version: Segments::RouteImage::VERSION)

      post admin_jobs_backfill_segment_route_images_path

      expect(Segments::BackfillRouteImagesJob).not_to have_been_enqueued
      expect(AdminEvent.count).to eq(0)
    end

    it "shows the segment image action" do
      create(:segment, user: member, route_image_version: 0)

      get admin_jobs_path

      expect(response.body).to include(I18n.t("admin.jobs.segment_route_images.action"))
    end
  end

  describe "loop reuse backfill" do
    before do
      sign_in_as(operator)
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    end

    it "enqueues the sweep for stale loops and audits the count" do
      workout = create(:workout, user: member, loop_reuse_version: 0)
      create(:segment, :loop, user: member, source_workout: workout)

      post admin_jobs_backfill_loop_reuse_path

      expect(response).to redirect_to(admin_jobs_path)
      expect(Segments::BackfillLoopReuseJob).to have_been_enqueued
      expect(AdminEvent.last).to have_attributes(action: "loop_reuse_backfill_enqueued", user: operator)
      expect(AdminEvent.last.metadata["count"]).to eq(1)
    end

    it "does not enqueue when every loop is reconciled" do
      post admin_jobs_backfill_loop_reuse_path

      expect(Segments::BackfillLoopReuseJob).not_to have_been_enqueued
      expect(AdminEvent.count).to eq(0)
    end

    it "shows the loop action" do
      workout = create(:workout, user: member, loop_reuse_version: 0)
      create(:segment, :loop, user: member, source_workout: workout)

      get admin_jobs_path

      expect(response.body).to include(I18n.t("admin.jobs.loop_reuse.action"))
    end
  end

  describe "elevation profile backfill" do
    before do
      sign_in_as(operator)
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    end

    it "enqueues the sweep for source-backed segments without a profile and audits the count" do
      create(:segment, user: member, source_workout: create(:workout, user: member))
      create(:segment, user: member, source_workout: create(:workout, user: member), elevation_profile: [])
      create(:segment, user: member)

      post admin_jobs_backfill_elevation_profiles_path

      expect(response).to redirect_to(admin_jobs_path)
      expect(Segments::BackfillElevationProfilesJob).to have_been_enqueued
      expect(AdminEvent.last).to have_attributes(action: "elevation_profiles_backfill_enqueued", user: operator)
      expect(AdminEvent.last.metadata["count"]).to eq(1)
    end

    it "does not enqueue when every profile is built" do
      create(:segment, user: member, source_workout: create(:workout, user: member), elevation_profile: [])

      post admin_jobs_backfill_elevation_profiles_path

      expect(Segments::BackfillElevationProfilesJob).not_to have_been_enqueued
      expect(AdminEvent.count).to eq(0)
    end

    it "shows the profile action" do
      create(:segment, user: member, source_workout: create(:workout, user: member))

      get admin_jobs_path

      expect(response.body).to include(I18n.t("admin.jobs.elevation_profiles.action"))
    end
  end

  describe "segment terrain elevation backfill" do
    before do
      sign_in_as(operator)
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    end

    it "enqueues the sweep for eligible courses and audits the count" do
      allow(Allure::Elevation::Config).to receive(:configured?).and_return(true)
      create(:segment, user: member, visibility: "public")
      create(:segment, user: member, visibility: "public", elevation_source: "dem", elevation_status: "ready")
      create(:segment, user: member)

      get admin_jobs_path
      expect(response.body).to include(I18n.t("admin.jobs.segment_terrain_elevation.action"))

      post admin_jobs_backfill_segment_terrain_elevation_path

      expect(response).to redirect_to(admin_jobs_path)
      expect(Segments::BackfillTerrainElevationJob).to have_been_enqueued
      expect(AdminEvent.last).to have_attributes(action: "segment_terrain_elevation_backfill_enqueued", user: operator)
      expect(AdminEvent.last.metadata["count"]).to eq(1)
    end

    it "does nothing without a provider" do
      create(:segment, user: member, visibility: "public")

      post admin_jobs_backfill_segment_terrain_elevation_path

      expect(Segments::BackfillTerrainElevationJob).not_to have_been_enqueued
      expect(AdminEvent.count).to eq(0)
    end
  end

  describe "segment place backfill" do
    before do
      sign_in_as(operator)
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    end

    it "enqueues the sweep for pending and failed segments and audits the count" do
      with_env("GEOCODING_BASE_URL" => "https://geocoding.test") do
        create(:segment, user: member, place_status: "pending")
        create(:segment, user: member, place_status: "failed")
        create(:segment, user: member, place_status: "ready", place_name: "Rochelune")

        get admin_jobs_path
        expect(response.body).to include(I18n.t("admin.jobs.segment_places.action"))

        post admin_jobs_backfill_segment_places_path

        expect(response).to redirect_to(admin_jobs_path)
        expect(Segments::BackfillPlacesJob).to have_been_enqueued
        expect(AdminEvent.last).to have_attributes(action: "segment_places_backfill_enqueued", user: operator)
        expect(AdminEvent.last.metadata["count"]).to eq(2)
      end
    end

    it "does nothing without a geocoding provider" do
      with_env("GEOCODING_BASE_URL" => nil) do
        create(:segment, user: member, place_status: "pending")

        get admin_jobs_path
        expect(response.body).not_to include(I18n.t("admin.jobs.segment_places.title"))

        post admin_jobs_backfill_segment_places_path

        expect(Segments::BackfillPlacesJob).not_to have_been_enqueued
        expect(AdminEvent.count).to eq(0)
      end
    end
  end

  describe "co-presence detection backfill" do
    before do
      sign_in_as(operator)
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    end

    it "enqueues the sweep over recordings the detector has not seen and audits the count" do
      create(:workout, user: member)
      create(:workout, user: member, together_detection_version: Allure::Together::Detector::VERSION)

      get admin_jobs_path
      expect(response.body).to include(I18n.t("admin.jobs.together_detection.action"))

      post admin_jobs_backfill_together_detection_path

      expect(response).to redirect_to(admin_jobs_path)
      expect(Together::BackfillDetectionJob).to have_been_enqueued
      expect(AdminEvent.last).to have_attributes(action: "together_detection_backfill_enqueued", user: operator)
      expect(AdminEvent.last.metadata["count"]).to eq(1)
    end

    it "does nothing once every recording was compared" do
      create(:workout, user: member, together_detection_version: Allure::Together::Detector::VERSION)

      post admin_jobs_backfill_together_detection_path

      expect(Together::BackfillDetectionJob).not_to have_been_enqueued
      expect(AdminEvent.count).to eq(0)
    end

    it "refuses anyone but the operator" do
      sign_in_as(member)

      post admin_jobs_backfill_together_detection_path

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "heart-rate backfill" do
    before do
      sign_in_as(operator)
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    end

    it "enqueues the sweep over recordings without a current histogram and audits the count" do
      create(:workout, user: member)
      create(:workout, user: member, heart_rate_version: Allure::HeartRate::Histogram::VERSION)
      create(:workout, :manual, user: member)

      get admin_jobs_path
      expect(response.body).to include(I18n.t("admin.jobs.heart_rate.action"))

      post admin_jobs_backfill_heart_rate_path

      expect(response).to redirect_to(admin_jobs_path)
      expect(HeartRates::BackfillJob).to have_been_enqueued
      expect(AdminEvent.last).to have_attributes(action: "heart_rate_backfill_enqueued", user: operator)
      expect(AdminEvent.last.metadata["count"]).to eq(1)
    end

    it "does nothing once every recording has its histogram" do
      create(:workout, user: member, heart_rate_version: Allure::HeartRate::Histogram::VERSION)

      post admin_jobs_backfill_heart_rate_path

      expect(HeartRates::BackfillJob).not_to have_been_enqueued
      expect(AdminEvent.count).to eq(0)
    end

    it "refuses anyone but the operator" do
      sign_in_as(member)

      post admin_jobs_backfill_heart_rate_path

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "route suggestion backfill" do
    before do
      sign_in_as(operator)
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    end

    it "enqueues one sweep per concerned account and audits the count" do
      create(:workout, user: member)
      create(:workout, user: member, route_suggestion_version: Segments::RouteSuggestionDetector::VERSION)

      get admin_jobs_path
      expect(response.body).to include(I18n.t("admin.jobs.route_suggestions.action"))

      post admin_jobs_backfill_route_suggestions_path

      expect(response).to redirect_to(admin_jobs_path)
      expect(Segments::RouteSuggestionSweepJob).to have_been_enqueued.with(member.id)
      expect(AdminEvent.last).to have_attributes(action: "route_suggestions_backfill_enqueued", user: operator)
      expect(AdminEvent.last.metadata["count"]).to eq(1)
    end

    it "does nothing once every recording was examined" do
      create(:workout, user: member, route_suggestion_version: Segments::RouteSuggestionDetector::VERSION)

      post admin_jobs_backfill_route_suggestions_path

      expect(Segments::RouteSuggestionSweepJob).not_to have_been_enqueued
      expect(AdminEvent.count).to eq(0)
    end

    it "refuses anyone but the operator" do
      sign_in_as(member)

      post admin_jobs_backfill_route_suggestions_path

      expect(response).to have_http_status(:not_found)
    end
  end

  def with_env(values)
    previous = values.to_h { |key, _value| [ key, ENV[key] ] }
    values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
