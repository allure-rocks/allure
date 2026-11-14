# frozen_string_literal: true

module Workouts
  # Rebuilds every source-derived value from the immutable original file while
  # preserving owner metadata and immutable publication snapshots. `force:`
  # re-runs an already-current workout: the sport change path needs it because
  # the stored metrics depend on the sport's thresholds.
  #
  # `elevation_source:` overrides the workout's effective source for this run
  # (`"device"` or `"dem"`). A `dem` run applies the cached terrain profile
  # before analysis and forces the DEM ascent class (PLAN_ELEVATION.md); without
  # it the stored effective source is reused.
  class Reanalyzer
    MissingOriginalFileError = OriginalTrack::MissingOriginalFileError
    USABLE_ELEVATION_STATUSES = Workouts::ElevationEnricher::USABLE_STATUSES

    # `track:` injects an already-parsed original, so the rebuild sweep parses
    # a file once for both its facts and its analysis
    # (PLAN_DERIVATIONS.md §3).
    def initialize(workout:, force: false, elevation_source: nil, track: nil)
      @workout = workout
      @force = force
      @elevation_source = elevation_source
      @track = track
    end

    def call!
      return @workout if current?
      raise MissingOriginalFileError, "workout has no original file" unless @workout.original_file.attached?

      track = parse_track
      recorded_elevation = track_elevation?(track)
      source = resolved_elevation_source
      track, source = apply_elevation_profile(track, source)
      metrics = analyze_track(track, source)
      device_totals = device_elevation_totals(track, metrics, source)
      # Computation before the row lock; persistence inside it still commits the
      # efforts with the metrics they derive from (PLAN_BEST_EFFORTS.md §4).
      efforts = BestEfforts::Rebuild.compute(
        sport: @workout.sport,
        segments: metrics.segments,
        workout_started_at: metrics.started_at,
        context: "reanalysis",
        anomalies: metrics.anomalies
      )
      heart_rate = HeartRates::Rebuild.compute(segments: metrics.segments)

      places_stale = false
      Workout.transaction do
        @workout.with_lock do
          return @workout if current?

          @geometry_changed = geometry_changed?(metrics.segments)
          places_stale = @geometry_changed || source != @workout.elevation_source
          @workout.update!(workout_attributes(metrics, source, recorded_elevation, device_totals))
          replace_track_segments(metrics.segments)
          replace_laps(track.laps)
          BestEfforts::Rebuild.new(workout: @workout, context: "reanalysis").persist(efforts)
          HeartRates::Rebuild.new(workout: @workout).persist(heart_rate)
        end
      end

      if places_stale
        refresh_toponymy
        refresh_weather
      end
      # A re-analysis can move the points a photo was placed against.
      PhotoPlacementJob.perform_later(@workout) if @workout.photos.exists?
      @workout
    end

    private

    def current?
      !@force && @workout.analysis_version >= Allure::Gpx::Analyzer::VERSION
    end

    def parse_track
      @track || OriginalTrack.new(workout: @workout).call
    end

    def analyze_track(track, source)
      Allure::Gpx::Analyzer.new(
        stopped_speed_threshold_km_h: @workout.sport.stopped_speed_threshold,
        records_elevation: @workout.sport.records_elevation,
        grade_adjusted_pace: @workout.sport.grade_adjusted_pace?,
        elevation_filter: (source == "dem" ? :dem : nil),
        speed_ceiling_km_h: @workout.sport.speed_ceiling_km_h
      ).analyze(track)
    end

    def resolved_elevation_source
      source = @elevation_source.presence || @workout.elevation_source
      source == "dem" ? "dem" : "device"
    end

    # The original file's profile, read before any terrain override: it decides
    # whether the owner has a recorded profile to fall back to.
    def track_elevation?(track)
      track.segments.any? do |segment|
        segment.points.any? { |point| Allure::Gpx::Elevation.valid?(point.elevation) }
      end
    end

    # Returns `[track, source]`. A `dem` run with no usable cached profile
    # degrades to the recorded profile instead of failing the reanalysis; the
    # effective source then follows the data that was actually analysed.
    def apply_elevation_profile(track, source)
      return [ track, "device" ] unless source == "dem"
      return [ track, "device" ] unless @workout.sport.records_elevation?

      profile = elevation_profile
      return [ track, "device" ] unless profile

      [ Allure::Elevation::TrackOverride.call(track, profile:), "dem" ]
    end

    def elevation_profile
      record = @workout.elevation
      return nil unless record&.status.in?(USABLE_ELEVATION_STATUSES)
      return nil if record.samples.empty?

      Allure::Elevation::Profile.new(record.samples)
    end

    # The device's own totals win over the computed profile when the file
    # carries them; a DEM run ignores them entirely, and so does a virtual
    # world, whose elevation is rendered rather than measured.
    def device_elevation_totals(track, metrics, source)
      return nil unless source == "device" && @workout.sport.records_elevation?

      DeviceElevationTotals.call(
        track:, distance: metrics.distance, virtual: @workout.sport.virtual?
      )
    end

    def workout_attributes(metrics, source, recorded_elevation, device_totals)
      {
        started_at: metrics.started_at,
        duration: metrics.duration,
        moving_time: metrics.moving_time,
        pause_time: metrics.pause_time,
        distance: metrics.distance,
        ascent: device_totals ? device_totals[:ascent] : metrics.ascent,
        descent: device_totals ? device_totals[:descent] : metrics.descent,
        min_elevation: metrics.min_elevation,
        max_elevation: metrics.max_elevation,
        average_speed: metrics.average_speed,
        max_speed: metrics.max_speed,
        average_pace: metrics.average_pace,
        best_pace: metrics.best_pace,
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
        data_anomalies: metrics.anomalies,
        contested_metrics: Allure::Gpx::Anomalies.contested_columns(metrics.anomalies),
        recorded_elevation:,
        grade_adjusted_pace: metrics.grade_adjusted_pace,
        elevation_source: source,
        # The run applied a concrete source: a pending user request is settled.
        elevation_source_requested: nil,
        # New track segments invalidate every point-indexed effort until the
        # matching job that follows each reanalysis stamps it again; automatic
        # publishing waits for that (PLAN_AUTO_PUBLISHING.md §4).
        loop_reuse_version: 0,
        route_image_version: route_image_version(metrics)
      }
    end

    # The owner image is drawn from the track geometry alone, so it only needs
    # a re-render when that geometry actually changed. A forced run (sport
    # change, elevation-source switch) keeps it by design; a versioned run
    # compares the stored and the recomputed coordinates, so an analyzer bump
    # that leaves a track untouched costs no re-render.
    def route_image_version(metrics)
      return @workout.route_image_version if @force
      return 0 if @geometry_changed

      @workout.route_image_version
    end

    # The stored places name positions and carry their elevations, so a new
    # track or a new elevation profile re-geocodes them; a same-geometry,
    # same-profile run (a sport change) keeps them (PLAN_DERIVATIONS.md §4).
    def refresh_toponymy
      ToponymyRefresh.new(workout: @workout).call
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name, workout_id: @workout.id })
    end

    # The weather plan reads the stored positions, times and elevations; an
    # unchanged plan converges offline from the kept responses.
    def refresh_weather
      WeatherRefresh.new(workout: @workout).call
    rescue StandardError => error
      Rails.error.report(error, handled: true, context: { component: self.class.name, workout_id: @workout.id })
    end

    # A nil geometry never compares equal to coordinates: a positionless
    # recording keeps its empty shape, and a versioned run that would move a
    # workout between shapes (only a changed parser rule can) is treated as a
    # change and re-renders nothing (PLAN_NO_GPS.md §6).
    def geometry_changed?(segments)
      stored = @workout.track_segments.map { |segment| segment.geom&.points&.map { |point| [ point.x, point.y ] } }
      stored != segments.map(&:coordinates)
    end

    def replace_track_segments(segments)
      @workout.track_segments.delete_all
      segments.each_with_index do |segment, index|
        @workout.track_segments.create!(
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
          average_heart_rate: segment.average_heart_rate,
          max_heart_rate: segment.max_heart_rate,
          average_cadence: segment.average_cadence,
          max_cadence: segment.max_cadence,
          average_power: segment.average_power,
          max_power: segment.max_power,
          geom: build_linestring(segment.coordinates),
          points: segment.points,
          points_count: segment.points.length,
          grade_adjusted_pace: segment.grade_adjusted_pace
        )
      end
    end

    def replace_laps(laps)
      @workout.laps.delete_all
      laps.each do |lap|
        @workout.laps.create!(
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

    # RGeo helpers. A positionless recording has no coordinates: both builders
    # answer nil and the columns stay empty, exactly as the importer stores
    # them (PLAN_NO_GPS.md §5).
    def factory = RGeo::Geographic.spherical_factory(srid: 4326)

    def build_point(lon_lat)
      return if lon_lat.nil?

      lon, lat = lon_lat
      factory.point(lon, lat)
    end

    def build_linestring(coordinates)
      return if coordinates.empty?

      factory.line_string(coordinates.map { |lon, lat| factory.point(lon, lat) })
    end
  end
end
