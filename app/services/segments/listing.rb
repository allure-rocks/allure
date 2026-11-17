# frozen_string_literal: true

module Segments
  # docs/dev/SEGMENTS.md: the board follows the reader. Eligibility is derived
  # on read for one viewer, with no stored snapshot and nothing to refresh. An
  # effort appears on a board for a viewer when:
  #
  # - the segment is an active, non-private course the viewer may see;
  # - its workout has an active publication the viewer may read
  #   (`WorkoutPublication.visible_to`, the feed's own rule) whose frozen
  #   profile snapshot shares the route: a course never reveals a passage
  #   whose publication hides where it went;
  # - the athlete has no `segment_opt_outs` row on that segment;
  # - no active privacy zone of the athlete intersects the segment corridor.
  #
  # Every condition is an INNER JOIN, an EXISTS or a NOT EXISTS, so a missing
  # publication or an unreadable input excludes the effort instead of
  # defaulting to visible. A workout published to several audiences
  # (docs/dev/PUBLISHING.md) qualifies through any of them and still ranks once.
  # A private course matches nothing, which keeps routes and loops (always
  # private) off every board. Two viewers may read two different boards.
  module Listing
    NOT_EXCLUDED = <<~SQL.squish
      NOT EXISTS (
        SELECT 1 FROM segment_opt_outs
        WHERE segment_opt_outs.segment_id = segment_efforts.segment_id
          AND segment_opt_outs.user_id = segment_efforts.user_id
      )
    SQL

    # The corridor is the segment geometry widened by its match tolerance; the
    # test runs on the M2 zone geometry (center + radius), exactly like the
    # owner-facing preflight.
    NOT_ZONED = <<~SQL.squish
      NOT EXISTS (
        SELECT 1 FROM privacy_zones
        WHERE privacy_zones.user_id = segment_efforts.user_id
          AND privacy_zones.active
          AND ST_DWithin(segments.geom, privacy_zones.center,
                         privacy_zones.radius_meters + segments.match_tolerance_meters)
      )
    SQL

    private_constant :NOT_EXCLUDED, :NOT_ZONED

    # The board views (DESIGN.md §20.7): every athlete the viewer may see, or
    # only the accounts they follow plus themselves.
    SCOPES = %w[everyone following].freeze

    # The eligible efforts of one segment or page of segments, unordered.
    def self.for_segment(segment, viewer:, scope: "everyone") = eligible(segment_ids: segment.id, viewer:, scope:)

    def self.for_segments(segment_ids, viewer:, scope: "everyone") = eligible(segment_ids: Array(segment_ids), viewer:, scope:)

    def self.eligible(segment_ids:, viewer:, scope: "everyone")
      all_eligible(viewer:, scope:).where(segment_id: segment_ids)
    end

    # The participant counter a viewer reads: the distinct athletes of their
    # own board, across sports (docs/dev/SEGMENTS.md). An unpublished effort
    # never shows through it, so it agrees with the board and « Mon rang ».
    def self.participants_count(segment, viewer:) = participants_counts(segment.id, viewer:).fetch(segment.id, 0)

    def self.participants_counts(segment_ids, viewer:)
      eligible(segment_ids: Array(segment_ids), viewer:).group(:segment_id).distinct.count(:user_id)
    end

    # Every effort the viewer may see on every course, for a query that
    # aggregates per segment (the index's record sort).
    def self.all_eligible(viewer:, scope: "everyone")
      return SegmentEffort.none if viewer.nil?

      relation = SegmentEffort
        .joins(:segment)
        .where(segments: { active: true })
        .where.not(segments: { visibility: "private" })
        .where(segment_id: Segment.visible_to(viewer).select(:id))
        .where(workout_id: qualifying_publication(viewer))
        .where(NOT_EXCLUDED)
        .where(NOT_ZONED)
      scope == "following" ? relation.where(user_id: following_user_ids(viewer) + [ viewer.id ]) : relation
    end

    # The local accounts the viewer follows (accepted), for the alias rule and
    # the « Mes abonnements » view.
    def self.following_user_ids(viewer)
      return [] if viewer&.actor.nil?

      Following.local_user_ids_followed_by(viewer.actor).pluck("users.id")
    end

    def self.qualifying_publication(viewer)
      WorkoutPublication.visible_to(viewer).route_shared.select(:workout_id)
    end
    private_class_method :qualifying_publication
  end
end
