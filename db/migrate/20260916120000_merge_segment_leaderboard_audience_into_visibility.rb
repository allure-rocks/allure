# frozen_string_literal: true

# PLAN_SEGMENTS.md §8.4 merge: one visibility axis now governs both the course
# page and its leaderboard. The translation is fail-closed — the new level is
# the most restrictive of the course visibility and the former board audience:
# owner → private, followers/members → followers_only, public → public.
#
# No `listed` backfill is needed: the former audience classes map one-to-one
# onto the surviving visibility classes (owner↔private, members/followers↔
# followers_only, public↔public), and `Segments::Listing` keys the same rules
# on `visibility` after this migration.
class MergeSegmentLeaderboardAudienceIntoVisibility < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE segments
      SET visibility = CASE LEAST(
        CASE visibility
          WHEN 'private' THEN 0
          WHEN 'followers_only' THEN 1
          ELSE 2
        END,
        CASE leaderboard_audience
          WHEN 'owner' THEN 0
          WHEN 'followers' THEN 1
          WHEN 'members' THEN 1
          ELSE 2
        END
      )
        WHEN 0 THEN 'private'
        WHEN 1 THEN 'followers_only'
        ELSE 'public'
      END
    SQL

    remove_check_constraint :segments, name: "segments_leaderboard_audience"
    remove_column :segments, :leaderboard_audience
  end

  def down
    add_column :segments, :leaderboard_audience, :string, default: "owner", null: false

    execute <<~SQL.squish
      UPDATE segments
      SET leaderboard_audience = CASE visibility
        WHEN 'private' THEN 'owner'
        WHEN 'followers_only' THEN 'followers'
        ELSE 'public'
      END
    SQL

    add_check_constraint :segments,
                         "leaderboard_audience IN (#{quoted(%w[owner members followers public])})",
                         name: "segments_leaderboard_audience"
  end

  private

  def quoted(values) = values.map { |value| "'#{value}'" }.join(", ")
end
