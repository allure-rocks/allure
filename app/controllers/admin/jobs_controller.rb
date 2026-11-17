# frozen_string_literal: true

module Admin
  # Background-job health with recovery controls. The panel polls a Turbo Frame
  # fragment; every mutation is audited and every destructive one is confirmed
  # in the shared dialog (PLAN_ADMIN.md §4.2).
  class JobsController < BaseController
    before_action :set_no_store

    def show
      @snapshot = Jobs::Snapshot.new.call
      if request.headers["Turbo-Frame"].blank?
        @rebuild_count = Workouts::BackfillRebuildJob.pending_scope.count
        @route_images_backfill_count = Workouts::BackfillRouteImagesJob.pending_scope.count
        @segment_route_images_backfill_count = Segments::BackfillRouteImagesJob.pending_scope.count
        @elevation_backfill_count = elevation_backfill_count
        @weather_backfill_count = Workouts::BackfillWeatherJob.pending_scope.count
        @places_backfill_count = places_backfill_count
        @toponymy_backfill_count = toponymy_backfill_count
        @loop_reuse_backfill_count = Segments::BackfillLoopReuseJob.pending_scope.count
        @elevation_profiles_backfill_count = Segments::BackfillElevationProfilesJob.pending_scope.count
        @segment_terrain_elevation_backfill_count = segment_terrain_elevation_backfill_count
        @segment_places_backfill_count = segment_places_backfill_count
        @together_detection_backfill_count = Together::BackfillDetectionJob.pending_scope.count
        @heart_rate_backfill_count = HeartRates::BackfillJob.pending_scope.count
        @route_suggestions_backfill_count = Segments::RouteSuggestionSweepJob.pending_scope.count
        return
      end

      render partial: "admin/jobs/live", locals: { snapshot: @snapshot }, layout: false
    end

    def retry_job
      failure = SolidQueue::FailedExecution.find(params[:id])
      job = failure.job
      failure.retry
      audit(:job_retried, class_name: job.class_name, queue_name: job.queue_name)
      redirect_to admin_jobs_path(anchor: "failed"), notice: t("admin.jobs.flash.job_retried")
    end

    def discard_job
      failure = SolidQueue::FailedExecution.find(params[:id])
      job = failure.job
      job.discard
      audit(:job_discarded, class_name: job.class_name, queue_name: job.queue_name)
      redirect_to admin_jobs_path(anchor: "failed"), notice: t("admin.jobs.flash.job_discarded")
    end

    def retry_all
      count = SolidQueue::FailedExecution.count
      if count.positive?
        SolidQueue::FailedExecution.retry_all(
          SolidQueue::Job.where(id: SolidQueue::FailedExecution.select(:job_id))
        )
      end
      audit(:jobs_retried, count:)
      redirect_to admin_jobs_path(anchor: "failed"), notice: t("admin.jobs.flash.jobs_retried", count:)
    end

    def discard_all
      count = SolidQueue::FailedExecution.count
      SolidQueue::FailedExecution.discard_all_in_batches if count.positive?
      audit(:jobs_discarded, count:)
      redirect_to admin_jobs_path(anchor: "failed"), notice: t("admin.jobs.flash.jobs_discarded", count:)
    end

    def pause_queue
      queue = find_queue!
      queue.pause
      audit(:queue_paused, queue: queue.name)
      redirect_to admin_jobs_path, notice: t("admin.jobs.flash.queue_paused", queue: queue.name)
    end

    def resume_queue
      queue = find_queue!
      queue.resume
      audit(:queue_resumed, queue: queue.name)
      redirect_to admin_jobs_path, notice: t("admin.jobs.flash.queue_resumed", queue: queue.name)
    end

    # Enqueues the versioned rebuild sweep (file-derived facts and analysis),
    # which self-reschedules in bounded batches. Read-only when every workout
    # is current.
    def rebuild
      count = Workouts::BackfillRebuildJob.pending_scope.count
      if count.positive?
        Workouts::BackfillRebuildJob.perform_later
        audit(:workouts_rebuild_enqueued, count:)
        redirect_to admin_jobs_path, notice: t("admin.jobs.flash.workouts_rebuild_enqueued", count:)
      else
        redirect_to admin_jobs_path, notice: t("admin.jobs.flash.workouts_rebuild_current")
      end
    end

    # Re-renders every owner route image that is missing or stale. Read-only
    # when every image is current; publication images are snapshot media and
    # are deliberately out of scope (docs/dev/DERIVATIONS.md).
    def backfill_route_images
      count = Workouts::BackfillRouteImagesJob.pending_scope.count
      if count.positive?
        Workouts::BackfillRouteImagesJob.perform_later
        audit(:route_images_backfill_enqueued, count:)
        redirect_to admin_jobs_path, notice: t("admin.jobs.flash.route_images_backfill_enqueued", count:)
      else
        redirect_to admin_jobs_path, notice: t("admin.jobs.flash.route_images_backfill_current")
      end
    end

    # Re-renders every owner segment image that is missing or stale. Read-only
    # when every image is current; publication images are snapshot media and
    # are deliberately out of scope (docs/dev/DERIVATIONS.md).
    def backfill_segment_route_images
      count = Segments::BackfillRouteImagesJob.pending_scope.count
      if count.positive?
        Segments::BackfillRouteImagesJob.perform_later
        audit(:segment_route_images_backfill_enqueued, count:)
        redirect_to admin_jobs_path, notice: t("admin.jobs.flash.segment_route_images_backfill_enqueued", count:)
      else
        redirect_to admin_jobs_path, notice: t("admin.jobs.flash.segment_route_images_backfill_current")
      end
    end

    # Enqueues the id-cursor terrain-elevation backfill for every eligible
    # workout. Read-only when there is nothing pending or no provider.
    def backfill_elevation
      count = elevation_backfill_count
      if count.positive?
        Workouts::BackfillElevationJob.perform_later
        audit(:elevation_backfill_enqueued, count:)
        redirect_to admin_jobs_path, notice: t("admin.jobs.flash.elevation_backfill_enqueued", count:)
      else
        redirect_to admin_jobs_path, notice: t("admin.jobs.flash.elevation_backfill_current")
      end
    end

    # Schedules the weather of every consenting account's eligible workouts
    # that have none or an older generation (PLAN_WEATHER.md §9). The weather
    # job is paced; read-only while the feature is off or nothing is pending.
    def backfill_weather
      count = Workouts::BackfillWeatherJob.pending_scope.count
      if count.positive?
        Workouts::BackfillWeatherJob.perform_later
        audit(:weather_backfill_enqueued, count:)
        redirect_to admin_jobs_path, notice: t("admin.jobs.flash.weather_backfill_enqueued", count:)
      else
        redirect_to admin_jobs_path, notice: t("admin.jobs.flash.weather_backfill_current")
      end
    end

    # Enqueues the id-cursor workout-place backfill for every usable toponymy
    # whose list is stale. Pure and offline; read-only when there is nothing
    # pending or no geocoding provider.
    def backfill_places
      count = places_backfill_count
      if count.positive?
        Workouts::BackfillPlacesJob.perform_later
        audit(:places_backfill_enqueued, count:)
        redirect_to admin_jobs_path, notice: t("admin.jobs.flash.places_backfill_enqueued", count:)
      else
        redirect_to admin_jobs_path, notice: t("admin.jobs.flash.places_backfill_current")
      end
    end

    # Re-geocodes every workout whose toponymy is missing or was built by an
    # older algorithm, and discards a legacy toponymy left on a virtual
    # workout (docs/dev/DERIVATIONS.md). It only schedules the globally paced
    # geocoding job; read-only when nothing is pending or no provider is set.
    def backfill_toponymy
      count = toponymy_backfill_count
      if count.positive?
        Workouts::BackfillToponymyJob.perform_later
        audit(:toponymy_backfill_enqueued, count:)
        redirect_to admin_jobs_path, notice: t("admin.jobs.flash.toponymy_backfill_enqueued", count:)
      else
        redirect_to admin_jobs_path, notice: t("admin.jobs.flash.toponymy_backfill_current")
      end
    end

    # Re-runs loop detection for workouts whose loop was not reconciled under
    # the current reuse predicate, so duplicate loop segments converge onto the
    # oldest similar one (docs/dev/DERIVATIONS.md). Read-only when nothing is
    # pending.
    def backfill_loop_reuse
      count = Segments::BackfillLoopReuseJob.pending_scope.count
      if count.positive?
        Segments::BackfillLoopReuseJob.perform_later
        audit(:loop_reuse_backfill_enqueued, count:)
        redirect_to admin_jobs_path, notice: t("admin.jobs.flash.loop_reuse_backfill_enqueued", count:)
      else
        redirect_to admin_jobs_path, notice: t("admin.jobs.flash.loop_reuse_backfill_current")
      end
    end

    # Builds the stored elevation profile of every source-backed segment that
    # does not have one yet (docs/dev/DERIVATIONS.md). Pure and offline;
    # read-only when nothing is pending.
    def backfill_elevation_profiles
      count = Segments::BackfillElevationProfilesJob.pending_scope.count
      if count.positive?
        Segments::BackfillElevationProfilesJob.perform_later
        audit(:elevation_profiles_backfill_enqueued, count:)
        redirect_to admin_jobs_path, notice: t("admin.jobs.flash.elevation_profiles_backfill_enqueued", count:)
      else
        redirect_to admin_jobs_path, notice: t("admin.jobs.flash.elevation_profiles_backfill_current")
      end
    end

    # Gives every eligible course the terrain service's elevation figures
    # (docs/dev/ELEVATION.md), through the paced per-course job. Read-only when
    # nothing is pending or no provider is set.
    def backfill_segment_terrain_elevation
      count = segment_terrain_elevation_backfill_count
      if count.positive?
        Segments::BackfillTerrainElevationJob.perform_later
        audit(:segment_terrain_elevation_backfill_enqueued, count:)
        redirect_to admin_jobs_path, notice: t("admin.jobs.flash.segment_terrain_elevation_backfill_enqueued", count:)
      else
        redirect_to admin_jobs_path, notice: t("admin.jobs.flash.segment_terrain_elevation_backfill_current")
      end
    end

    # Geocodes the nearby place of every course still pending or failed
    # (PLAN_SEGMENTS.md §8.4), through the paced geocoding job. Read-only when
    # nothing is pending or no provider is set.
    def backfill_segment_places
      count = segment_places_backfill_count
      if count.positive?
        Segments::BackfillPlacesJob.perform_later
        audit(:segment_places_backfill_enqueued, count:)
        redirect_to admin_jobs_path, notice: t("admin.jobs.flash.segment_places_backfill_enqueued", count:)
      else
        redirect_to admin_jobs_path, notice: t("admin.jobs.flash.segment_places_backfill_current")
      end
    end

    # Compares every recording the current detector has not seen with its
    # owner's partners on the same outing (docs/dev/SHARED-ACTIVITIES.md). Suggestions
    # for old outings reach both accounts once.
    def backfill_together_detection
      count = Together::BackfillDetectionJob.pending_scope.count
      if count.positive?
        Together::BackfillDetectionJob.perform_later
        audit(:together_detection_backfill_enqueued, count:)
        redirect_to admin_jobs_path, notice: t("admin.jobs.flash.together_detection_backfill_enqueued", count:)
      else
        redirect_to admin_jobs_path, notice: t("admin.jobs.flash.together_detection_backfill_current")
      end
    end

    # Compares every recording the current detector has not seen with the
    # account's other recordings, newest first, to suggest the routes the owner
    # repeats (PLAN_SEGMENTS.md §7.7). Nothing is created: a suggestion appears
    # on the concerned activity.
    def backfill_route_suggestions
      count = Segments::RouteSuggestionSweepJob.pending_scope.count
      if count.positive?
        Segments::RouteSuggestionSweepJob.enqueue_all
        audit(:route_suggestions_backfill_enqueued, count:)
        redirect_to admin_jobs_path, notice: t("admin.jobs.flash.route_suggestions_backfill_enqueued", count:)
      else
        redirect_to admin_jobs_path, notice: t("admin.jobs.flash.route_suggestions_backfill_current")
      end
    end

    # Computes the heart-rate histogram of every recording the current version
    # has not seen, from the stored points (docs/dev/HEART-RATE.md).
    def backfill_heart_rate
      count = HeartRates::BackfillJob.pending_scope.count
      if count.positive?
        HeartRates::BackfillJob.perform_later
        audit(:heart_rate_backfill_enqueued, count:)
        redirect_to admin_jobs_path, notice: t("admin.jobs.flash.heart_rate_backfill_enqueued", count:)
      else
        redirect_to admin_jobs_path, notice: t("admin.jobs.flash.heart_rate_backfill_current")
      end
    end

    private

    def segment_places_backfill_count
      return 0 unless Allure::Toponyms::Config.configured?

      Segments::BackfillPlacesJob.pending_scope.count
    end

    def segment_terrain_elevation_backfill_count
      return 0 unless Allure::Elevation::Config.configured?

      Segments::BackfillTerrainElevationJob.pending_scope.count
    end

    def elevation_backfill_count
      return 0 unless Allure::Elevation::Config.configured?

      Workouts::BackfillElevationJob.pending_scope.count
    end

    def places_backfill_count
      return 0 unless Allure::Toponyms::Config.configured?

      Workouts::BackfillPlacesJob.pending_scope.count
    end

    def toponymy_backfill_count
      return 0 unless Allure::Toponyms::Config.configured?

      Workouts::BackfillToponymyJob.pending_scope.count
    end

    # Only a queue that exists in the queue database can be paused, so an
    # arbitrary path segment is never passed through.
    def find_queue!
      name = params[:queue_name].to_s
      known = SolidQueue::Job.distinct_values_of(:queue_name) | SolidQueue::Pause.pluck(:queue_name)
      raise ActiveRecord::RecordNotFound unless known.include?(name)

      SolidQueue::Queue.find_by_name(name)
    end

    def audit(action, metadata)
      Audit.record(actor: current_user, action:, metadata: metadata.compact)
    end

    def set_no_store
      response.set_header("Cache-Control", "no-store")
    end
  end
end
