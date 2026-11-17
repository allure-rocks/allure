# frozen_string_literal: true

module Segments
  # Who sees the viewer on a course's board, or why nobody does
  # (docs/dev/SEGMENTS.md, DESIGN.md §20.6). The board follows each reader, so
  # the athlete's own line states the widest reach of their efforts:
  #
  # - `public` — a public publication sharing the route: every member who sees
  #   the course;
  # - `followers` — only a followers publication sharing the route: their
  #   accepted followers;
  # - `opted_out`, `zoned` — they left this board, or one of their privacy
  #   zones touches the corridor;
  # - `route_hidden` — published, but no publication shares the route;
  # - `unpublished` — no live publication at all;
  # - `credited` — only efforts credited from another account's recording,
  #   which shared boards never rank (docs/dev/SHARED-ACTIVITIES.md);
  # - nil — no effort on the course, or a course without a board.
  class Reach
    def initialize(segment:, user:)
      @segment = segment
      @user = user
    end

    def call
      return nil if @user.nil? || !@segment.shareable? || !@segment.active?

      all_efforts = @segment.segment_efforts.where(user_id: @user.id)
      return nil unless all_efforts.exists?
      return "opted_out" if @segment.opted_out?(@user)
      return "zoned" if zoned?

      efforts = all_efforts.joins(:workout).merge(Workout.recordings)
      return "credited" unless efforts.exists?

      publications = WorkoutPublication.active.where(workout_id: efforts.select(:workout_id))
      return "unpublished" unless publications.exists?

      shared = publications.route_shared
      return "public" if shared.where(audience: "public").exists?
      return "followers" if shared.exists?

      "route_hidden"
    end

    private

    def zoned?
      PrivacyZone
        .where(user_id: @user.id, active: true)
        .where(
          "ST_DWithin(privacy_zones.center, (SELECT geom FROM segments WHERE id = ?), " \
          "privacy_zones.radius_meters + ?)",
          @segment.id, @segment.match_tolerance_meters
        )
        .exists?
    end
  end
end
