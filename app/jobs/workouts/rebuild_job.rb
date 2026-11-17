# frozen_string_literal: true

module Workouts
  # The single file-derived reconciliation of a workout (docs/dev/DERIVATIONS.md).
  # One parse serves every phase, in dependency order:
  #
  # 1. facts, when the stored import-detection generation is older: fill the
  #    recording device when empty or a superseded manufacturer name, re-detect a sport whose import entry is
  #    still `detected`, and re-locate a virtual venue (discarding a legacy
  #    toponymy);
  # 2. analysis, when the stored analyzer generation is older: recompute
  #    metrics, track segments and best efforts, then re-match segments and
  #    detected laps;
  # 3. local assemblies: the displayed place list (pure, from stored toponymy);
  # 4. media: enqueue the owner route image when it is missing or stale.
  #
  # A file that cannot be parsed is reported and the workout is left
  # un-stamped, so it stays visible as pending in the rebuild counts.
  class RebuildJob < ApplicationJob
    queue_as :default

    retry_on ActiveRecord::Deadlocked, ActiveRecord::ConnectionNotEstablished,
             ActiveRecord::SerializationFailure, wait: :polynomially_longer, attempts: 5
    discard_on ActiveJob::DeserializationError
    discard_on ActiveRecord::RecordNotFound

    def perform(workout)
      track = OriginalTrack.new(workout:).call
      reconcile_facts(workout, track) if facts_stale?(workout)
      reanalyze(workout, track) if analysis_stale?(workout)
      # A positionless recording has no toponymy to name and no route image to
      # render; its smart laps are rebuilt by the laps job instead of the
      # segment matcher (docs/dev/NO-GPS.md).
      if workout.reload.positioned?
        PlaceNamer.new(workout:).call
        enqueue_route_image(workout)
      else
        rebuild_laps(workout)
      end
    rescue OriginalTrack::MissingOriginalFileError, Allure::Gpx::Error, Allure::Fit::Error,
           SportChange::MissingOriginalFile, SportChange::ReanalysisFailed => error
      Rails.error.report(error, handled: true, context: { component: self.class.name, workout_id: workout.id })
    end

    private

    def facts_stale?(workout)
      workout.import_detection_version < ImportDetection::VERSION
    end

    def analysis_stale?(workout)
      workout.analysis_version < Allure::Gpx::Analyzer::VERSION
    end

    def reconcile_facts(workout, track)
      apply_source(workout, track)
      apply_sport(workout, track)
      settle_virtual_venue(workout)
      workout.update_column(:import_detection_version, ImportDetection::VERSION)
    end

    def apply_source(workout, track)
      return if track.creator.blank?
      return if workout.source.present? && !ImportDetection::SUPERSEDED_DEVICE_NAMES.include?(workout.source)

      workout.update_column(:source, track.creator)
    end

    # Only a sport the import itself resolved may be corrected: a hand-picked
    # sport (`manual`), an import fallback, and a workout with no ledger row
    # are left alone. A file that resolves nothing is a no-op, not a failure.
    def apply_sport(workout, track)
      entry = WorkoutImportEntry.find_by(workout_id: workout.id)
      return unless entry&.sport_source == "detected"

      resolution = SportResolver.new(user: workout.user, track:).call
      return if resolution.sport.nil? || resolution.sport.id == workout.sport_id

      SportChange.new(workout:, sport: resolution.sport, provenance: "detected", track:).call!
    rescue SportResolver::MissingSport
      nil
    end

    def settle_virtual_venue(workout)
      workout.reload
      return unless workout.sport.virtual?

      workout.toponymy&.destroy!
      VirtualVenueNamer.new(workout:).call
    end

    # A facts pass may have changed the sport, and SportChange already forced
    # the re-analysis (with this very track), so the staleness check runs after
    # the facts phase on the reloaded workout.
    def reanalyze(workout, track)
      Reanalyzer.new(workout:, track:).call!
      return unless workout.reload.positioned?

      Segments::MatchWorkoutJob.perform_later(workout)
    end

    # A positionless recording's derived laps and records are rebuilt without
    # the segment matcher: there is no geometry to match against.
    def rebuild_laps(workout)
      workout.update_columns(loop_reuse_version: Segments::LoopReuse::VERSION)
      Laps::RebuildJob.perform_later(workout)
    end

    def enqueue_route_image(workout)
      return unless workout.route_image_version < RouteImage::VERSION

      RenderRouteImageJob.perform_later(workout)
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name, workout_id: workout.id })
    end
  end
end
