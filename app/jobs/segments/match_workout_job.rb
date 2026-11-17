# frozen_string_literal: true

module Segments
  class MatchWorkoutJob < ApplicationJob
    queue_as :default

    # A circuit must be travelled at least twice to count as a loop (annex §4.8).
    MIN_LOOP_OCCURRENCES = 2

    retry_on ActiveRecord::Deadlocked, ActiveRecord::ConnectionNotEstablished,
             ActiveRecord::SerializationFailure, ActiveRecord::RecordNotUnique,
             wait: :polynomially_longer, attempts: 5
    discard_on ActiveJob::DeserializationError
    discard_on ActiveRecord::RecordNotFound

    # One match at a time per account: a segment backfill fans out one job per
    # candidate workout, and an account's jobs share its segments, loops and
    # owner lock. Waiting in Solid Queue holds no thread nor connection, unlike
    # waiting on the row locks below, which stay as the guard once the
    # concurrency duration expires.
    limits_concurrency key: ->(workout) { "segments-match-#{workout.user_id}" }, duration: 15.minutes

    def perform(workout)
      return perform_credit(workout) if workout.credit?

      @created_efforts = []
      @touched_segment_ids = Set.new
      Segment.transaction do
        # Two jobs for the same workout can overlap: the importer enqueues one
        # while an elevation reanalysis or a segment backfill enqueues another.
        # The row lock serializes them, so the second run re-reads the committed
        # efforts instead of racing the unique (segment, workout, occurrence)
        # index. Points are read after the lock so a waiting run sees the
        # segments the previous run left.
        workout.lock!
        points = Allure::Segments::PointStream.new(
          segments: workout.track_segments,
          workout_started_at: workout.started_at
        ).call

        remove_stale_efforts(workout)
        Segments::CandidateQuery.for_workout(workout).find_each do |segment|
          persist_matches(workout, segment, points)
        end
        Segments::CandidateQuery.for_route_workout(workout).find_each do |route|
          persist_matches(workout, route, points)
        end
        detect_and_persist_loop(workout, points)
        workout.update_columns(loop_reuse_version: Segments::LoopReuse::VERSION)
        Laps::Rebuild.new(workout:, points:).call
      end

      refresh_touched_segments
      # The biggest-climb record reads the freshly rebuilt detected climbs.
      Records::RecomputeService.new(user: workout.user, sport: workout.sport).call
      Webhooks::Events.segment_efforts_created(workout, @created_efforts || [])
      Workouts::AutoPublishJob.nudge(workout)
      # The credited biggest climb follows the rebuilt climbs (docs/dev/SHARED-ACTIVITIES.md).
      Participations::CreditSyncJob.nudge(workout)
    end

    private

    # A credit row is matched for its participant on its source's points
    # (docs/dev/SHARED-ACTIVITIES.md): plain segments only — routes, loops and laps
    # are the owner's analysis — and kinematics only. A detached row has no
    # points left and keeps its frozen efforts.
    def perform_credit(credit)
      source = credit.credited_from
      return unless source

      @created_efforts = []
      @touched_segment_ids = Set.new
      Segment.transaction do
        credit.lock!
        points = Allure::Segments::PointStream.new(
          segments: source.track_segments,
          workout_started_at: source.started_at
        ).call

        remove_stale_efforts(credit)
        Segments::CandidateQuery.for_workout(credit).find_each do |segment|
          persist_matches(credit, segment, points)
        end
      end

      refresh_touched_segments
      Records::RecomputeService.new(user: credit.user, sport: credit.sport).call
      Webhooks::Events.segment_efforts_created(credit, @created_efforts)
    end

    def remove_stale_efforts(workout)
      workout.segment_efforts.where.not(matcher_version: Allure::Segments::Matcher::VERSION).delete_all
    end

    def persist_matches(workout, segment, points)
      # Taken before any of the segment's efforts is written, so a concurrent
      # deletion (`FOR UPDATE` first) and this match meet on the segment row
      # instead of on each other's efforts. A segment deleted since the
      # candidates were read is skipped, not fatal.
      return unless Segment.where(id: segment.id).lock("FOR KEY SHARE").pick(:id)

      matches = Allure::Segments::Matcher.new(
        segment: segment,
        points: points,
        stopped_speed_threshold_km_h: workout.sport.stopped_speed_threshold,
        grade_adjusted_pace: workout.sport.grade_adjusted_pace?,
        elevation_filter: workout.elevation_filter
      ).call
      existing = workout.segment_efforts.where(segment:).index_by(&:occurrence_index)
      occurrence_indexes = matches.map(&:occurrence_index)

      if occurrence_indexes.empty?
        workout.segment_efforts.where(segment:).delete_all
      else
        workout.segment_efforts.where(segment:).where.not(occurrence_index: occurrence_indexes).delete_all
      end
      matches.each do |match|
        effort = existing.fetch(match.occurrence_index) do
          workout.segment_efforts.build(segment: segment)
        end
        effort.assign_attributes(
          user: workout.user,
          sport: workout.sport,
          occurrence_index: match.occurrence_index,
          started_at: match.started_at,
          elapsed_time: match.elapsed_time,
          moving_time: match.moving_time,
          distance: match.distance,
          ascent: match.ascent,
          descent: match.descent,
          average_speed: match.average_speed,
          average_pace: match.average_pace,
          # A credit row's effort is kinematics only: the channels are the
          # source owner's (docs/dev/SHARED-ACTIVITIES.md).
          average_heart_rate: (match.average_heart_rate if workout.recording?),
          max_heart_rate: (match.max_heart_rate if workout.recording?),
          average_cadence: (match.average_cadence if workout.recording?),
          average_power: (match.average_power if workout.recording?),
          max_power: (match.max_power if workout.recording?),
          start_offset_meters: match.start_offset_meters,
          start_point_index: match.start_point_index,
          end_point_index: match.end_point_index,
          deviation_meters: match.deviation_meters,
          grade_adjusted_pace: match.grade_adjusted_pace,
          personal_best: false,
          anonymous: false,
          matcher_version: Allure::Segments::Matcher::VERSION
        )
        created = effort.new_record?
        effort.save!
        (@created_efforts ||= []) << effort if created
      end

      refresh_segment(segment)
    end

    # Counters and personal-best flags derived from the segment's current
    # efforts. Also used when efforts are released or dropped, so a loop still
    # shared with another workout keeps truthful totals. Only noted here: the
    # refresh rewrites every athlete's efforts on the segment, so running it
    # inside the matching transaction made two matches of one segment wait on
    # each other's efforts and deadlock.
    def refresh_segment(segment)
      @touched_segment_ids << segment.id
    end

    # Each segment is refreshed after the commit, in its own short transaction
    # and in id order.
    def refresh_touched_segments
      Segment.where(id: @touched_segment_ids.to_a).order(:id).each { |segment| Segments::Refresh.call(segment) }
    end

    # A detected circuit becomes a `kind: "loop"` segment owned by the account,
    # matched to find every traversal. A similar loop already owned by the
    # account is reused instead of creating another private segment, so the
    # same circuit keeps one name and one owner image across workouts; a
    # genuinely different circuit creates one. Tracks are immutable, so a
    # re-run converges to the same row. A candidate with too few traversals is
    # not a new loop and is dropped; a known loop needs only one traversal.
    def detect_and_persist_loop(workout, points)
      # The owner row serializes loop reconciliation: two concurrent imports of
      # the same circuit must not each create their own segment. The second run
      # then finds the first run's committed loop through `LoopReuse`.
      workout.user.lock!

      detection = Segments::LoopDetection.new(workout:, points:).call
      if detection.nil?
        release_loop_efforts(workout)
        destroy_orphan_loops(workout)
        return
      end

      loop_segment = detection.segment || create_loop_segment(workout, detection.candidate)
      if loop_segment.nil?
        release_loop_efforts(workout)
        destroy_orphan_loops(workout)
        return
      end

      relax_loop_sport(loop_segment, workout)
      release_loop_efforts(workout, keep: loop_segment)
      persist_matches(workout, loop_segment, points)
      drop_under_lapped_workout(workout, loop_segment, minimum: detection.segment ? 1 : MIN_LOOP_OCCURRENCES)
      destroy_orphan_loops(workout)
    end

    def create_loop_segment(workout, candidate)
      segment = Segments::Creator.new(
        user: workout.user,
        workout: workout,
        kind: "loop",
        name: loop_name(workout),
        start_index: candidate.start_index,
        end_index: candidate.end_index
      ).call
      segment if segment.persisted?
    end

    # Loops are owner-only analysis, not shareable courses: the same circuit
    # recorded under two sports widens to "all sports" instead of creating a
    # second segment.
    def relax_loop_sport(segment, workout)
      return if segment.sport_id.nil? || segment.sport_id == workout.sport_id

      segment.update_columns(sport_id: nil)
    end

    # One workout keeps a single loop effort set: this releases its efforts
    # from every loop but `keep` (nil releases all). Loops that survive refresh
    # their counters, so a loop shared with another workout stays truthful.
    def release_loop_efforts(workout, keep: nil)
      ids = workout.segment_efforts.joins(:segment).where(segments: { kind: "loop" })
        .distinct.pluck(:segment_id)
      ids -= [ keep.id ] if keep
      return if ids.empty?

      workout.segment_efforts.where(segment_id: ids).delete_all
      @touched_segment_ids.merge(ids)
    end

    # Discovery requires repetition; recognition of an existing loop does not.
    def drop_under_lapped_workout(workout, segment, minimum:)
      return if segment.segment_efforts.where(workout:).count >= minimum

      segment.segment_efforts.where(workout:).delete_all
      refresh_segment(segment)
    end

    # A loop without a single effort carries no information: it was created and
    # never matched, or every workout that used it has released it. A loop the
    # owner renamed is not derived data any more — it is kept until the owner
    # removes it (PLAN_SEGMENTS.md §7.3). Rows are locked and re-read before the
    # delete: a rename committed while this job waited is never destroyed. The
    # owner lock makes the sweep safe while another of the account's match jobs
    # runs.
    def destroy_orphan_loops(workout)
      orphan_ids = Segment.where(user_id: workout.user_id, kind: "loop")
        .where.missing(:segment_efforts)
        .ids
      Segment.where(id: orphan_ids).lock("FOR UPDATE").find_each do |segment|
        next if segment.renamed?

        segment.destroy! if segment.segment_efforts.empty?
      end
    end

    def loop_name(workout)
      name = workout.title.presence ? "#{workout.title} loop" : "Loop"
      name.truncate(120)
    end
  end
end
