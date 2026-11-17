# frozen_string_literal: true

# docs/dev/REACTIONS.md: a reaction remembers the audience it was given
# through, so a reader is named only the reactors whose audience they may
# read. Counts stay global. Existing rows are classified fail-closed: a
# workout reaction is public only when a public publication of its workout
# was live at the moment of the reaction; a received note's is the note's.
class AddAudienceToReactions < ActiveRecord::Migration[8.1]
  def up
    add_column :reactions, :audience, :string

    execute <<~SQL.squish
      UPDATE reactions SET audience = remote_notes.audience
      FROM remote_notes
      WHERE reactions.remote_note_id = remote_notes.id
    SQL

    execute <<~SQL.squish
      UPDATE reactions SET audience = CASE WHEN EXISTS (
        SELECT 1 FROM workout_publications
        WHERE workout_publications.workout_id = reactions.workout_id
          AND workout_publications.audience = 'public'
          AND workout_publications.status IN ('active', 'deleted')
          AND workout_publications.published_at <= reactions.created_at
          AND (workout_publications.deleted_at IS NULL OR workout_publications.deleted_at > reactions.created_at)
      ) THEN 'public' ELSE 'followers' END
      WHERE reactions.workout_id IS NOT NULL
    SQL

    execute "UPDATE reactions SET audience = 'followers' WHERE audience IS NULL"

    change_column_null :reactions, :audience, false
    add_check_constraint :reactions, "audience IN ('public', 'followers')", name: "reactions_audience"
  end

  def down
    remove_check_constraint :reactions, name: "reactions_audience"
    remove_column :reactions, :audience
  end
end
