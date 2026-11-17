# frozen_string_literal: true

module Segments
  class CandidateQuery
    # The prefilter mirrors the matcher's endpoint search exactly. It must not be
    # stricter, or a matchable segment would never be offered to the matcher, and
    # widening it is pointless because Fréchet rejects those pairs anyway.
    # A workout matches its owner's segments plus other users' shared
    # (`visibility != private`) segments. Routes stay owner-scoped; they are
    # never shared. A credit row is matched for its participant on its
    # source's track (docs/dev/SHARED-ACTIVITIES.md); a detached one has none.
    def self.for_workout(workout)
      track = workout.track_workout
      return Segment.none unless track

      shared = Segment.where(active: true, kind: "segment")
      shared
        .where(user_id: workout.user_id)
        .or(shared.where.not(visibility: "private"))
        .where(distance: ..workout.distance)
        .where(sport_id: [ nil, workout.sport_id ])
        .where(<<~SQL.squish, workout_id: track.id)
          EXISTS (
            SELECT 1
            FROM track_segments AS candidate_track_segments
            WHERE candidate_track_segments.workout_id = :workout_id
              AND ST_DWithin(
                candidate_track_segments.geom,
                segments.start_point,
                segments.match_tolerance_meters
              )
          )
          AND EXISTS (
            SELECT 1
            FROM track_segments AS candidate_track_segments
            WHERE candidate_track_segments.workout_id = :workout_id
              AND ST_DWithin(
                candidate_track_segments.geom,
                segments.end_point,
                segments.match_tolerance_meters
              )
          )
        SQL
    end

    # A route is a whole track, so the matching workout is about the same length.
    # The prefilter only guards against a route far longer than the workout; the
    # matcher's ±10 % window and endpoint check make the final call.
    #
    # `minimum_tolerance:` widens the endpoint search for a caller that judges
    # the route at a larger tolerance than the one it was saved with — the
    # recurring-route detector, so a recording that resembles an existing route
    # at the route default is never suggested as a new one (PLAN_SEGMENTS.md
    # §7.7). The matcher still applies the route's own tolerance unless the
    # caller widens its copy too.
    def self.for_route_workout(workout, minimum_tolerance: nil)
      Segment
        .where(active: true, kind: "route", user_id: workout.user_id)
        .where(
          "segments.distance * ? <= ?",
          Allure::Segments::Matcher::ROUTE_MIN_LENGTH_RATIO,
          workout.distance
        )
        .where(sport_id: [ nil, workout.sport_id ])
        .where(<<~SQL.squish, workout_id: workout.id, minimum_tolerance:)
          EXISTS (
            SELECT 1
            FROM track_segments AS candidate_track_segments
            WHERE candidate_track_segments.workout_id = :workout_id
              AND ST_DWithin(
                candidate_track_segments.geom,
                segments.start_point,
                GREATEST(segments.match_tolerance_meters, COALESCE(:minimum_tolerance, 0))
              )
          )
          AND EXISTS (
            SELECT 1
            FROM track_segments AS candidate_track_segments
            WHERE candidate_track_segments.workout_id = :workout_id
              AND ST_DWithin(
                candidate_track_segments.geom,
                segments.end_point,
                GREATEST(segments.match_tolerance_meters, COALESCE(:minimum_tolerance, 0))
              )
          )
        SQL
    end

    # Known loops are owner-only analysis, independently of new-loop discovery.
    # Sport is deliberately ignored, as in LoopReuse; a match widens the stored
    # loop to all sports. A complete traversal must fit one recording segment.
    def self.for_loop_workout(workout)
      return Segment.none unless workout.recording? && workout.positioned?

      Segment.where(active: true, kind: "loop", user_id: workout.user_id)
        .where("segments.distance * ? <= ?", Allure::Segments::Matcher::MIN_LENGTH_RATIO, workout.distance)
        .where(<<~SQL.squish, workout_id: workout.id)
          EXISTS (
            SELECT 1 FROM track_segments AS candidate_track_segments
            WHERE candidate_track_segments.workout_id = :workout_id
              AND ST_DWithin(candidate_track_segments.geom, segments.start_point, segments.match_tolerance_meters)
              AND ST_DWithin(candidate_track_segments.geom, segments.end_point, segments.match_tolerance_meters)
          )
        SQL
    end

    # A private segment backfills its owner's workouts. A shared segment
    # backfills every user's workouts; eligibility is derived on read by
    # `Segments::Listing`, so ineligible rows stay invisible. An attached
    # credit row is a candidate through its source's track; a detached one has
    # none. Routes and loops are owner analysis, never matched on a credit row.
    def self.for_segment(segment)
      return Workout.none unless segment.active

      query = Workout.where(distance: distance_window(segment))
      query = query.where(origin: "import") unless segment.kind == "segment"
      query = query.where(user_id: segment.user_id) if segment.visibility == "private"
      query = query.where(<<~SQL.squish, segment.start_point, segment.match_tolerance_meters, segment.end_point, segment.match_tolerance_meters)
        EXISTS (
          SELECT 1
          FROM track_segments AS candidate_track_segments
          WHERE candidate_track_segments.workout_id = COALESCE(workouts.credited_from_workout_id, workouts.id)
            AND ST_DWithin(candidate_track_segments.geom, ?, ?)
        )
        AND EXISTS (
          SELECT 1
          FROM track_segments AS candidate_track_segments
          WHERE candidate_track_segments.workout_id = COALESCE(workouts.credited_from_workout_id, workouts.id)
            AND ST_DWithin(candidate_track_segments.geom, ?, ?)
        )
      SQL
      query = query.where(sport_id: segment.sport_id) if segment.sport_id
      query.order(:id)
    end

    def self.distance_window(segment)
      if segment.kind == "route"
        from = segment.distance.to_d * Allure::Segments::Matcher::ROUTE_MIN_LENGTH_RATIO
        from..(segment.distance.to_d * Allure::Segments::Matcher::ROUTE_MAX_LENGTH_RATIO)
      else
        (segment.distance.to_d * Allure::Segments::Matcher::MIN_LENGTH_RATIO)..
      end
    end
  end
end
