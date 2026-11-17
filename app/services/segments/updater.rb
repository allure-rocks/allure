# frozen_string_literal: true

module Segments
  class Updater
    # Changing the sport changes which workouts are eligible, so it is a
    # matching change: existing efforts are rebuilt.
    MATCHING_ATTRIBUTES = %w[match_tolerance_meters active sport_id].freeze

    def initialize(segment:, attributes:, zone_acknowledged: false)
      @segment = segment
      @attributes = attributes
      @zone_acknowledged = zone_acknowledged
    end

    def call
      # Only an explicitly submitted attribute can change matching; an absent
      # key (e.g. sharing without touching tolerance) must never delete
      # efforts.
      matching_changed = MATCHING_ATTRIBUTES.any? do |attribute|
        @attributes.key?(attribute) &&
          @segment.public_send(attribute).to_s != @attributes[attribute].to_s
      end

      save_segment(matching_changed)

      # Sharing (private → shared visibility) backfills other users' past
      # workouts via the widened candidate query. Existing efforts are kept;
      # the visibility-change refresh relists them.
      visibility_change = @segment.saved_change_to_visibility
      shared_now = visibility_change && visibility_change.first == "private" && visibility_change.last != "private"

      Segments::BackfillSegmentJob.perform_later(@segment) if @segment.persisted? && (matching_changed || shared_now)
      @segment
    end

    private

    # A loop's manual edit runs under the owner row lock — the same one the
    # account's match jobs hold — so a rename can never interleave with a
    # reconciliation that would release its efforts or delete it
    # (PLAN_SEGMENTS.md §7.3).
    def save_segment(matching_changed)
      if @segment.kind == "loop"
        @segment.user.with_lock { persist(matching_changed) }
      else
        persist(matching_changed)
      end
    end

    def persist(matching_changed)
      Segment.transaction do
        # Re-read under the lock: a loop a just-committed job has deleted is
        # gone, and the edit must fail visibly rather than vanish.
        @segment.reload if @segment.kind == "loop"
        @segment.assign_attributes(@attributes)
        # A loop's rename makes it the owner's own; the mark is never taken
        # back. Other kinds are named by the owner at creation already.
        # (PLAN_SEGMENTS.md §7.3)
        @segment.renamed_at = Time.current if @segment.kind == "loop" && @segment.will_save_change_to_name?
        if matching_changed
          @segment.segment_efforts.where.not(id: frozen_efforts.select(:id)).delete_all
          Segments::Refresh.call(@segment)
          # The corridor is the geometry widened by the match tolerance, so a
          # tolerance change invalidates an older acknowledgment and asks the
          # owner again (PLAN_SEGMENTS_FEDERATION.md §5.2).
          @segment.privacy_zone_acknowledged_at = nil
        end
        @segment.privacy_zone_acknowledged_at = Time.current if @zone_acknowledged
        # A failed save must not leave partially applied matching side effects
        # (deleted efforts, zeroed counters, a cleared acknowledgment).
        raise ActiveRecord::Rollback unless @segment.save
      end
    end

    # A detached credit row has no points left to match again, so its efforts
    # survive a matching change while the segment stays active and its sport
    # still admits them (docs/dev/SHARED-ACTIVITIES.md). Read after the new attributes
    # are assigned.
    def frozen_efforts
      return SegmentEffort.none unless @segment.active

      scope = @segment.segment_efforts.joins(:workout)
        .where(workouts: { origin: "credit", credited_from_workout_id: nil })
      scope = scope.where(sport_id: @segment.sport_id) if @segment.sport_id
      scope
    end
  end
end
