# frozen_string_literal: true

require "digest"

module Workouts
  class Importer
    MAX_BYTES = 25.megabytes
    ALLOWED_EXTENSIONS = Allure::ImportFormat::EXTENSIONS
    # Control characters and Unicode line breaks, replaced before an upload's
    # text reaches the log.
    LOG_BREAKS = /[[:cntrl:]\u0085\u2028\u2029]/

    class ImportError < StandardError
      attr_reader :errors

      def initialize(errors = [])
        @errors = Array(errors)
        super(@errors.first)
      end
    end

    Result = Data.define(:workout, :success, :errors, :duplicate, :sport_source) do
      def success? = success
      def failure? = !success
      def duplicate? = duplicate
    end

    def initialize(user:, uploaded_file:, sport:, title: nil, description: nil, notes: nil,
                   filename: nil, source_digest: nil, equipment_ids: nil, commute: nil,
                   import_connection: nil, external_id: nil, bulk: false,
                   declared_sport: nil, near_duplicate_window: nil, time_shift: nil)
      @user = user
      @uploaded_file = uploaded_file
      @sport = sport
      @title = title
      @description = description
      @notes = notes
      @filename = filename
      @source_digest = source_digest
      @equipment_ids = equipment_ids
      @commute = commute
      # A remote import names its connection and the provider's id, written
      # with the workout (docs/dev/REMOTE-IMPORTS.md).
      @import_connection = import_connection
      @external_id = external_id
      # A bulk import (a large file batch, a date-range retrieval) is never
      # published automatically (docs/dev/AUTO-PUBLISHING.md).
      @bulk = bulk
      # The sport another service's metadata names, which outranks the file's
      # detection (PLAN_STRAVA_ARCHIVE.md §4).
      @declared_sport = declared_sport
      # When set, a recording already starting within this window is the same
      # outing imported another way, and this one is a duplicate
      # (PLAN_STRAVA_ARCHIVE.md §7).
      @near_duplicate_window = near_duplicate_window
      # An offset in seconds applied to the parsed track before anything is
      # derived from it (PLAN_DEMO.md §4): the demo seed dates its recordings
      # near the present. Persisted on the workout so every re-analysis of the
      # original re-applies it. Every ordinary import leaves it unset.
      @time_shift = time_shift
      # Resolved from the file's own bytes by validate_upload!.
      @format = nil
    end

    def call
      validate_upload!
      @source_digest ||= digest_upload
      track = parse_track
      # The shift precedes every derivation, so metrics, laps, efforts and the
      # near-duplicate window all read the same shifted times
      # (PLAN_DEMO.md §4).
      track = track.shifted(@time_shift) if @time_shift.to_i.nonzero?
      resolution = resolve_sport(track)
      metrics = analyze_track(track, resolution.sport)
      if (near = near_duplicate(metrics.started_at))
        return Result.new(workout: near, success: false, errors: [ I18n.t("workouts.import.errors.duplicate") ],
                          duplicate: true, sport_source: nil)
      end

      blob = create_blob
      begin
        workout = persist_workout(metrics, blob, track, resolution.sport)
        # A bulk import's enrichments run behind new outings (BacklogPriority).
        BacklogPriority.enqueue(active: @bulk) { enqueue_enrichments(workout) }
        Result.new(
          workout: workout,
          success: true,
          errors: [],
          duplicate: false,
          sport_source: resolution.source
        )
      rescue ActiveRecord::RecordNotUnique
        purge_blob(blob)
        Result.new(
          workout: nil,
          success: false,
          errors: [ I18n.t("workouts.import.errors.duplicate") ],
          duplicate: true,
          sport_source: nil
        )
      rescue StandardError => e
        purge_blob(blob)
        raise e unless e.is_a?(ActiveRecord::RecordInvalid) || e.is_a?(ActiveRecord::StatementInvalid)

        # Validation failures surface as their translated messages; a
        # database refusal is reported for the operator and never shown, since
        # its text carries SQL.
        Result.new(workout: nil, success: false, errors: [ failure_message(e) ], duplicate: false, sport_source: nil)
      end
    rescue ImportError => e
      Result.new(workout: nil, success: false, errors: e.errors, duplicate: false, sport_source: nil)
    end

    def call!
      result = call
      raise ImportError, result.errors unless result.success?

      result.workout
    end

    private

    def validate_upload!
      errors = []

      if @uploaded_file.nil?
        errors << I18n.t("workouts.import.errors.missing_file")
        raise ImportError, errors
      end

      file = file_object(@uploaded_file)

      if file.size > MAX_BYTES
        errors << I18n.t("workouts.import.errors.too_large", max: I18n.t("workouts.import.max_size"))
      end

      filename = file_name(file)
      ext = File.extname(filename.to_s).downcase
      if ext.present? && Allure::ImportFormat.for_extension(ext).nil?
        errors << I18n.t("workouts.import.errors.unsupported_format")
      elsif ext.blank?
        errors << I18n.t("workouts.import.errors.missing_extension")
      end

      # The uploaded content type is not checked. Browsers report `.fit` as
      # any of application/octet-stream, application/vnd.ant.fit, or nothing
      # at all depending on the platform, so an allowlist only produces false
      # rejections. The magic-byte sniff below is strictly stronger and is
      # what decides how the file is parsed and stored.
      @format = Allure::ImportFormat.detect(file)
      errors << I18n.t("workouts.import.errors.unsupported_format") if @format.nil?

      raise ImportError, errors if errors.any?
    end

    def parse_track
      file = file_object(@uploaded_file)
      file.rewind if file.respond_to?(:rewind)
      @format.parser.parse(file)
    rescue Allure::Fit::MalformedFitError => error
      log_rejection("malformed FIT", error)
      raise ImportError, I18n.t("workouts.import.errors.malformed_fit")
    rescue Allure::Fit::UnsupportedFitError
      raise ImportError, I18n.t("workouts.import.errors.unsupported_fit_type")
    rescue Allure::Gpx::MalformedXmlError => error
      log_rejection("malformed XML", error)
      raise ImportError, I18n.t("workouts.import.errors.malformed")
    rescue Allure::Gpx::UnsupportedGpxError
      raise ImportError, I18n.t("workouts.import.errors.unsupported_format")
    rescue Allure::Gpx::NoTrackError
      raise ImportError, I18n.t("workouts.import.errors.no_track")
    rescue Allure::Gpx::TooManyPointsError
      raise ImportError, I18n.t("workouts.import.errors.too_many_points")
    rescue Allure::Gpx::MissingTimestampError
      raise ImportError, I18n.t("workouts.import.errors.missing_time")
    rescue Allure::Gpx::NonMonotonicTimestampError
      raise ImportError, I18n.t("workouts.import.errors.reversed_time")
    rescue Allure::Gpx::InvalidPointError
      raise ImportError, I18n.t("workouts.import.errors.invalid_point")
    rescue Allure::Gpx::Error, Allure::Fit::Error => e
      raise ImportError, e.message
    end

    # The localized message stays generic for the user; the parser detail goes
    # to the log so an operator can diagnose the rejected source. Logging must
    # never turn a rejection into a crash. The file name and the parser detail
    # both come from the upload, so neither may start a forged log line.
    def log_rejection(reason, error)
      name = @filename.presence || (@uploaded_file.original_filename if @uploaded_file.respond_to?(:original_filename))
      Rails.logger.warn("workout import rejected: #{reason} in #{log_text(name, 255).presence || 'unknown source'}: " \
                        "#{log_text(error.message, 500)}")
    rescue StandardError
      nil
    end

    def log_text(value, limit)
      value.to_s.scrub.gsub(LOG_BREAKS, " ").truncate(limit)
    end

    # A credit row is not a recording, so a credited outing does not stop the
    # participant's own recording of it (docs/dev/SHARED-ACTIVITIES.md).
    def near_duplicate(started_at)
      return nil unless @near_duplicate_window && started_at

      @user.workouts.recordings
        .where(started_at: (started_at - @near_duplicate_window)..(started_at + @near_duplicate_window))
        .min_by { |workout| (workout.started_at - started_at).abs }
    end

    def resolve_sport(track)
      Workouts::SportResolver.new(user: @user, track:, fallback_sport: @sport, declared_sport: @declared_sport).call
    rescue Workouts::SportResolver::MissingSport
      raise ImportError, I18n.t("workouts.import.errors.missing_sport")
    end

    def analyze_track(track, sport)
      Allure::Gpx::Analyzer.new(
        stopped_speed_threshold_km_h: sport.stopped_speed_threshold,
        records_elevation: sport.records_elevation,
        grade_adjusted_pace: sport.grade_adjusted_pace?,
        speed_ceiling_km_h: sport.speed_ceiling_km_h
      ).analyze(track)
    rescue Allure::Gpx::NonMonotonicTimestampError
      raise ImportError, I18n.t("workouts.import.errors.reversed_time")
    end

    def create_blob
      file = file_object(@uploaded_file)
      file.rewind if file.respond_to?(:rewind)
      filename = safe_filename
      blob = ActiveStorage::Blob.create_after_unfurling!(
        io: file,
        filename: filename,
        content_type: @format.content_type,
        identify: false
      )
      blob.upload_without_unfurling(file)
      blob
    rescue StandardError
      purge_blob(blob)
      raise
    end

    def persist_workout(metrics, blob, track, sport)
      totals = device_elevation_totals(track, metrics, sport)
      # The CPU computation runs before the transaction starts, so the
      # `users` row lock taken by every workout insert is not held during it.
      # Persistence stays inside the transaction (PLAN_BEST_EFFORTS.md §4).
      efforts = BestEfforts::Rebuild.compute(
        sport:,
        segments: metrics.segments,
        workout_started_at: metrics.started_at,
        context: "import",
        anomalies: metrics.anomalies
      )
      heart_rate = HeartRates::Rebuild.compute(segments: metrics.segments)

      Workout.transaction do
        workout = @user.workouts.create!(
          sport: sport,
          title: resolved_title(metrics, track, sport),
          description: resolved_description(track),
          notes: @notes.presence,
          # The file's own `commuting` statement is a fact and always wins; the
          # owner can clear it afterwards from the workout form.
          commute: @commute || track.commute_hint,
          started_at: metrics.started_at,
          duration: metrics.duration,
          moving_time: metrics.moving_time,
          pause_time: metrics.pause_time,
          distance: metrics.distance,
          ascent: totals ? totals[:ascent] : metrics.ascent,
          descent: totals ? totals[:descent] : metrics.descent,
          min_elevation: metrics.min_elevation,
          max_elevation: metrics.max_elevation,
          average_speed: metrics.average_speed,
          max_speed: metrics.max_speed,
          average_pace: metrics.average_pace,
          best_pace: metrics.best_pace,
          grade_adjusted_pace: metrics.grade_adjusted_pace,
          average_heart_rate: metrics.average_heart_rate,
          max_heart_rate: metrics.max_heart_rate,
          average_cadence: metrics.average_cadence,
          max_cadence: metrics.max_cadence,
          average_power: metrics.average_power,
          max_power: metrics.max_power,
          calories: metrics.calories,
          start_point: build_point(metrics.start_point),
          bounds: metrics.bounds,
          points_count: metrics.points_count,
          analysis_version: Allure::Gpx::Analyzer::VERSION,
          elevation_filter: metrics.elevation_filter&.to_s,
          time_shift_seconds: @time_shift.to_i,
          data_anomalies: metrics.anomalies,
          contested_metrics: Allure::Gpx::Anomalies.contested_columns(metrics.anomalies),
          recorded_elevation: metrics.min_elevation.present?,
          import_format: @format.key,
          source: track.creator.presence,
          source_digest: @source_digest,
          import_connection: @import_connection,
          external_id: @external_id
        )

        metrics.segments.each_with_index do |segment, index|
          workout.track_segments.create!(
            position: index,
            started_at: segment.started_at,
            duration: segment.duration,
            moving_time: segment.moving_time,
            pause_time: segment.pause_time,
            distance: segment.distance,
            ascent: segment.ascent,
            descent: segment.descent,
            min_elevation: segment.min_elevation,
            max_elevation: segment.max_elevation,
            average_speed: segment.average_speed,
            max_speed: segment.max_speed,
            average_pace: segment.average_pace,
            best_pace: segment.best_pace,
            grade_adjusted_pace: segment.grade_adjusted_pace,
            average_heart_rate: segment.average_heart_rate,
            max_heart_rate: segment.max_heart_rate,
            average_cadence: segment.average_cadence,
            max_cadence: segment.max_cadence,
            average_power: segment.average_power,
            max_power: segment.max_power,
            geom: build_linestring(segment.coordinates),
            points: segment.points,
            points_count: segment.points.length
          )
        end

        persist_laps(workout, track)
        BestEfforts::Rebuild.new(workout:, context: "import").persist(efforts)
        HeartRates::Rebuild.new(workout:).persist(heart_rate)
        Equipments::Totals.sync(workout, @equipment_ids)

        workout.original_file.attach(blob)

        workout
      end
    end

    # Recorded laps come straight from the source file (a FIT `lap` message or
    # a GPX `<lap>` element) via the parser, so no re-derivation from points.
    # A file that recorded none simply persists none.
    def persist_laps(workout, track)
      track.laps.each do |lap|
        workout.laps.create!(
          number: lap.number,
          started_at: lap.started_at,
          elapsed_time: lap.elapsed_time,
          moving_time: lap.moving_time,
          distance: lap.distance,
          ascent: lap.ascent,
          descent: lap.descent,
          average_speed: lap.average_speed,
          max_speed: lap.max_speed,
          average_pace: lap.average_pace,
          average_heart_rate: lap.average_heart_rate,
          max_heart_rate: lap.max_heart_rate,
          average_cadence: lap.average_cadence,
          average_power: lap.average_power,
          lap_trigger: lap.lap_trigger
        )
      end
    end

    # Everything geography-driven is skipped for a positionless recording
    # (docs/dev/NO-GPS.md): no venue, no route image, no segment matching, no
    # co-presence detection, no terrain elevation, no toponymy. Smart laps,
    # best efforts and records are derived from the points inside the
    # persistence transaction or by their own job.
    def enqueue_enrichments(workout)
      if workout.positioned?
        assign_virtual_venue(workout)
        enqueue_route_image(workout)
        enqueue_segment_matching(workout)
        enqueue_together_detection(workout)
        enqueue_route_suggestion(workout) unless @bulk
        enqueue_elevation(workout)
        enqueue_toponymy(workout)
        enqueue_weather(workout)
      else
        enqueue_laps(workout)
      end
      enroll_auto_publication(workout)
      Webhooks::Events.workout_created(workout)
    end

    def enqueue_route_image(workout)
      Workouts::RenderRouteImageJob.perform_later(workout)
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name, workout_id: workout.id })
    end

    def enqueue_segment_matching(workout)
      Segments::MatchWorkoutJob.perform_later(workout)
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name, workout_id: workout.id })
    end

    # A positionless recording has no geometry to match, so it derives its
    # smart laps and records directly (docs/dev/NO-GPS.md). The loop generation
    # is stamped at import: no loop or route effort will ever arrive for it.
    def enqueue_laps(workout)
      workout.update_columns(loop_reuse_version: Segments::LoopReuse::VERSION)
      Laps::RebuildJob.perform_later(workout)
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name, workout_id: workout.id })
    end

    # Co-presence detection (docs/dev/SHARED-ACTIVITIES.md) reads only the stored points.
    def enqueue_together_detection(workout)
      Together::DetectWorkoutJob.perform_later(workout)
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name, workout_id: workout.id })
    end

    # A recurring route is suggested, never created (PLAN_SEGMENTS.md §7.7).
    # A bulk import skips the per-recording pass: the end of its batch runs the
    # account sweep instead, newest first, so the suggestion's reference is the
    # most recent occurrence.
    def enqueue_route_suggestion(workout)
      Segments::SuggestRouteJob.perform_later(workout)
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name, workout_id: workout.id })
    end

    # A virtual workout has no real-world geography: the platform's venue
    # catalog names its place, synchronously, and no geocoding is enqueued.
    def assign_virtual_venue(workout)
      Workouts::VirtualVenueNamer.new(workout:).call
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name, workout_id: workout.id })
    end

    # The pending row tells the owner's page that places are on their way. When
    # terrain elevation was requested, the re-analysis that applies it
    # schedules the geocoding (or the apply job does when it gives up), so the
    # markers are named and elevated once, on the final profile.
    def enqueue_toponymy(workout)
      return if workout.sport.virtual?

      if workout.elevation_source_requested.present?
        workout.create_toponymy!(status: "pending", algorithm_version: Workouts::ToponymyEnricher::ALGORITHM_VERSION)
      else
        Workouts::ToponymyRefresh.new(workout:).call
      end
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name, workout_id: workout.id })
    end

    # Weather is fetched for an account that consented (PLAN_WEATHER.md §5);
    # the refresh itself checks every condition. Like the geocoding, it waits
    # for a requested terrain profile, whose re-analysis (or the apply job
    # giving up) schedules it on the final elevations.
    def enqueue_weather(workout)
      return if workout.elevation_source_requested.present?

      Workouts::WeatherRefresh.new(workout:).call
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name, workout_id: workout.id })
    end

    # Terrain elevation is fetched and applied only for a workout whose
    # recorded profile is empty, on a sport that records elevation, for an
    # account that opted in (docs/dev/ELEVATION.md).
    def enqueue_elevation(workout)
      return unless Allure::Elevation::Config.configured?
      return unless workout.sport.records_elevation?
      return unless workout.user.elevation_enrichment_enabled?
      return if workout.recorded_elevation?

      # The pending request is the marker automatic publishing waits on; the
      # apply job clears it once the terrain profile is applied or given up.
      workout.update_column(:elevation_source_requested, "dem")
      Workouts::ApplyElevationSourceJob.perform_later(workout, "dem")
    rescue StandardError => error
      workout.update_column(:elevation_source_requested, nil) if workout.persisted?
      Rails.error.report(error, handled: true, context: { component: self.class.name, workout_id: workout.id })
    end

    # An automatic publication is a side effect of the import, never a reason
    # for it to fail.
    def enroll_auto_publication(workout)
      Workouts::AutoPublicationEnrollment.new(workout:, bulk: @bulk).call
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name, workout_id: workout.id })
    end

    # The device's own totals win over the computed profile when the file
    # carries them (docs/dev/ELEVATION.md). Sports that ignore elevation keep
    # the computed zero.
    def device_elevation_totals(track, metrics, sport)
      return nil unless sport.records_elevation?

      Workouts::DeviceElevationTotals.call(track:, distance: metrics.distance, virtual: sport.virtual?)
    end

    def purge_blob(blob)
      return unless blob&.persisted?
      return if blob.attachments.exists?

      blob.purge
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name })
    end

    def failure_message(error)
      return error.message if error.is_a?(ActiveRecord::RecordInvalid)

      Rails.error.report(error, handled: true, context: { component: self.class.name, user_id: @user.id })
      I18n.t("workouts.import.errors.not_saved")
    end

    def resolved_title(metrics, track, sport)
      return @title.strip if @title.present? && @title.strip.present?
      return track.name.strip if track.name.present? && track.name.strip.present?

      sport_name = begin
        sport.translated_name
      rescue I18n::MissingTranslationData
        sport.label
      end
      I18n.t("workouts.defaults.title",
             sport: sport_name,
             date: I18n.l(metrics.started_at.in_time_zone(@user.time_zone).to_date))
    end

    def resolved_description(track)
      return @description.strip if @description.present? && @description.strip.present?

      track.description.presence
    end

    # RGeo helpers. A positionless recording has no coordinates at all, so
    # both builders answer nil and the columns stay empty (docs/dev/NO-GPS.md).
    def factory = RGeo::Geographic.spherical_factory(srid: 4326)

    def build_point(lon_lat)
      return if lon_lat.nil?

      lon, lat = lon_lat
      factory.point(lon, lat)
    end

    def build_linestring(coordinates)
      return if coordinates.empty?

      points = coordinates.map { |lon, lat| factory.point(lon, lat) }
      factory.line_string(points)
    end

    # The stored name follows the detected format, not the uploaded one, so a
    # mislabelled file is never kept under a misleading extension.
    def safe_filename
      raw = file_name(file_object(@uploaded_file)).to_s
      base = File.basename(raw, File.extname(raw)).parameterize.presence || "workout"
      "#{base[0, 100]}#{@format.extension}"
    end

    def file_object(file)
      file
    end

    def file_name(file)
      return @filename.to_s if @filename.present?

      if file.respond_to?(:original_filename) && file.original_filename.present?
        file.original_filename
      elsif file.respond_to?(:filename) && file.filename.present?
        file.filename.to_s
      else
        "workout.gpx"
      end
    end

    def digest_upload
      file = file_object(@uploaded_file)
      file.rewind if file.respond_to?(:rewind)
      digest = Digest::SHA256.new
      while (chunk = file.read(64 * 1024))
        digest.update(chunk)
      end
      file.rewind if file.respond_to?(:rewind)
      digest.hexdigest
    end
  end
end
