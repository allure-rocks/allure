# frozen_string_literal: true

module Segments
  # Suggests saving a recurring route as a `kind: route` course
  # (PLAN_SEGMENTS.md §7.7). The verdict is the route matcher itself
  # (`Allure::Segments::Matcher`, kind "route"): a suggestion is created only
  # when this recording and at least MIN_OCCURRENCES - 1 earlier recordings
  # would be attached to the route saved from this recording. Nothing is
  # persisted as a course; the suggestion is owner-only bookkeeping, and the
  # owner still decides whether to save the route or to dismiss it.
  #
  # The same detector serves a fresh import (one recording at a time) and the
  # audited history sweep (one account from its newest recording to its
  # oldest), so a suggestion's reference workout is always the most recent
  # occurrence the walk reached first.
  class RouteSuggestionDetector
    # Bump when the candidate query, the verdict, or the minimum changes, so
    # the history sweep re-examines the recordings it has not seen.
    VERSION = 1
    MIN_OCCURRENCES = 3
    MAX_CANDIDATES = 50
    DEFAULT_TOLERANCE = Segments::Creator::ROUTE_MATCH_TOLERANCE_METERS
    # The prefilter is wider than the matcher's ±10 % window: it only bounds
    # the recordings the matcher reads, never decides the match.
    CANDIDATE_LENGTH_RATIO = 0.15

    def self.call(workout) = new(workout).call

    def initialize(workout)
      @workout = workout
    end

    def call
      return unless eligible?
      return stamp if already_classified?
      return stamp if matches_existing_route?

      suggestion = join_existing_suggestion
      suggestion ||= create_suggestion
      stamp
      suggestion
    end

    private

    def eligible?
      return false unless @workout.recording? && @workout.positioned?
      return false if @workout.user.deactivated?
      return false if points.length < 2
      return false if points.any? { |point| point.longitude.nil? || point.latitude.nil? }

      true
    end

    def already_classified?
      RouteSuggestionWorkout.exists?(workout_id: @workout.id)
    end

    # A recording already covered by a route needs no suggestion: the route
    # form's own matcher would attach it. Checked here rather than through the
    # stored efforts, because the import enqueues this job independently of
    # Segments::MatchWorkoutJob. An existing route is judged at the detection
    # tolerance, not only at the one it was saved with: a recording that
    # resembles a saved route at 100 m must not be suggested as a new one.
    def matches_existing_route?
      Segments::CandidateQuery.for_route_workout(@workout, minimum_tolerance: DEFAULT_TOLERANCE).any? do |route|
        matcher(segment: widened_route(route), points:).call.any?
      end
    end

    # The route's geometry at the larger of its own tolerance and the detection
    # tolerance. An unsaved copy, so the stored route is never reinterpreted.
    def widened_route(route)
      tolerance = [ route.match_tolerance_meters, DEFAULT_TOLERANCE ].max
      return route if tolerance == route.match_tolerance_meters

      Segment.new(
        kind: "route",
        distance: route.distance,
        match_tolerance_meters: tolerance,
        signature: route.signature,
        geom: route.geom
      )
    end

    # A later recording of a circuit already suggested joins it, whatever the
    # suggestion's state: a dismissed suggestion keeps absorbing the repeats
    # without ever showing again. The reference's geometry is the canonical
    # comparison, so every member is a recording the saved route would match.
    def join_existing_suggestion
      @workout.user.route_suggestions
        .where(status: %w[pending dismissed])
        .where(sport_id: @workout.sport_id)
        .order(:id)
        .find do |suggestion|
          reference = suggestion.effective_reference_workout
          next false unless reference&.positioned?

          reference_preview = preview_for(reference)
          next false if reference_preview.nil?

          matcher(segment: reference_preview, points:).call.any?
        end
        &.tap { |suggestion| add_member(suggestion) }
    end

    # The recording that forms the suggestion is its reference: the route form
    # is built from it, so the saved route matches every member the banner
    # counts.
    def create_suggestion
      matches = candidate_workouts.select { |candidate| matches?(candidate) }
      return if matches.length + 1 < MIN_OCCURRENCES

      RouteSuggestion.transaction do
        # Serializes suggestion creation for one account, like loop
        # reconciliation: two imports of the same circuit must not each create
        # their own suggestion.
        @workout.user.lock!
        next if already_classified?

        suggestion = @workout.user.route_suggestions.create!(
          sport: @workout.sport,
          reference_workout: @workout,
          status: "pending"
        )
        RouteSuggestionWorkout.create!(route_suggestion: suggestion, workout: @workout)
        matches.each { |candidate| RouteSuggestionWorkout.create!(route_suggestion: suggestion, workout: candidate) }
        suggestion
      end
    rescue ActiveRecord::RecordNotUnique
      # Another suggestion claimed one of the recordings first; the next pass
      # joins it instead.
      nil
    end

    def add_member(suggestion)
      RouteSuggestionWorkout.find_or_create_by!(route_suggestion: suggestion, workout: @workout)
    rescue ActiveRecord::RecordNotUnique
      nil
    end

    # The recordings the matcher may compare: the owner's positioned
    # recordings of the same sport, near the same start and end, in the route
    # length window, not already classified and not already covered by a
    # route. Newest first, bounded.
    def candidate_workouts
      tolerance = DEFAULT_TOLERANCE
      end_point = factory.point(*points.last.coordinate)
      minimum = preview.distance * (1 - CANDIDATE_LENGTH_RATIO)
      maximum = preview.distance * (1 + CANDIDATE_LENGTH_RATIO)

      @workout.user.workouts
        .positioned
        .where(sport_id: @workout.sport_id)
        .where.not(id: @workout.id)
        .where(distance: minimum..maximum)
        .where.not(id: RouteSuggestionWorkout.select(:workout_id))
        .where.not(id: SegmentEffort.joins(:segment).where(segments: { kind: "route" }).select(:workout_id))
        .where(<<~SQL.squish, @workout.start_point, tolerance, end_point, tolerance)
          ST_DWithin(workouts.start_point, ?, ?)
          AND EXISTS (
            SELECT 1
            FROM track_segments AS candidate_track_segments
            WHERE candidate_track_segments.workout_id = workouts.id
              AND ST_DWithin(candidate_track_segments.geom, ?, ?)
          )
        SQL
        .order(started_at: :desc, id: :desc)
        .limit(MAX_CANDIDATES)
        .to_a
    end

    def matches?(candidate)
      candidate_points = point_stream_for(candidate)
      return false if candidate_points.length < 2

      matcher(segment: preview, points: candidate_points).call.any?
    end

    def matcher(segment:, points:)
      Allure::Segments::Matcher.new(
        segment:,
        points:,
        stopped_speed_threshold_km_h: @workout.sport.stopped_speed_threshold,
        grade_adjusted_pace: @workout.sport.grade_adjusted_pace?,
        elevation_filter: @workout.elevation_filter
      )
    end

    def points
      @points ||= point_stream_for(@workout)
    end

    def point_stream_for(workout)
      Allure::Segments::PointStream.new(
        segments: workout.track_segments,
        workout_started_at: workout.started_at
      ).call
    end

    def preview
      @preview ||= preview_for(@workout)
    end

    def preview_for(workout)
      @previews ||= {}
      @previews[workout.id] ||= begin
        stream = point_stream_for(workout)
        build_preview(stream) if stream.length >= 2
      end
    end

    # An unsaved route built exactly like Segments::Creator builds one: the
    # whole flattened stream, its measured length, and its shape signature.
    def build_preview(stream)
      coordinates = stream.map(&:coordinate)
      Segment.new(
        kind: "route",
        distance: stream.last.distance - stream.first.distance,
        match_tolerance_meters: DEFAULT_TOLERANCE,
        signature: Allure::Geometry::ShapeSignature.compute(coordinates),
        geom: factory.line_string(coordinates.map { |longitude, latitude| factory.point(longitude, latitude) })
      )
    end

    def factory
      @factory ||= RGeo::Geographic.spherical_factory(srid: 4326)
    end

    def stamp
      @workout.update_columns(route_suggestion_version: VERSION)
      nil
    end
  end
end
