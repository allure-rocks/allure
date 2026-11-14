# frozen_string_literal: true

# PLAN_SEGMENTS.md §6.3/§8.2 alignment: every active publication is treated as
# if its profile had carried `segment: true`, so the leaderboards that existed
# before the switch keep their rows and the opt-out model applies to all
# existing data at once. This is a controlled snapshot write, the same class of
# exception as WorkoutPublication#attach_sanitized_route_image!: the settings
# object is local policy metadata, and Federation::Serializers::WorkoutNote
# only reads `route_image` and `gpx` from it, so no federated payload changes.
# Later publications freeze the value themselves; nothing here is recomputed.
class AlignPublicationSnapshotsWithSegmentSetting < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE workout_publications
      SET profile_snapshot = jsonb_set(profile_snapshot, '{settings,segment}', 'true'::jsonb, true)
      WHERE status = 'active'
        AND profile_snapshot -> 'settings' -> 'segment' IS NULL
    SQL
  end

  def down
    # One-way data migration: stripping the key would silently unlist every
    # effort that predates the alignment, including ones whose publication was
    # created legitimately with the setting on.
  end
end
