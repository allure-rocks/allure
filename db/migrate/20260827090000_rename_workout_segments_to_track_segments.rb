# frozen_string_literal: true

# `WorkoutSegment` means a *recording* segment: one contiguous GPX <trkseg>
# between pauses. The sport-tracking domain also calls a reusable, leaderboarded
# portion of a course a "segment" (see docs/dev/SEGMENTS.md), and that concept needs
# the plain `Segment` constant.
#
# Renaming the M1 concept rather than the new one is the cheaper and safer
# direction: `workout_segments` appears in no URL, no serialized payload, and no
# federation contract. It is purely internal, and nothing has federated yet.
#
# `TrackSegment` is the GPX-native name (<trkseg> is literally a track segment)
# and it lines up with the existing /workouts/:id/track endpoint: a track is
# made of track segments.
class RenameWorkoutSegmentsToTrackSegments < ActiveRecord::Migration[8.1]
  OLD_NAME = "workout_segments"
  NEW_NAME = "track_segments"

  def up
    rename_table OLD_NAME.to_sym, NEW_NAME.to_sym
    rename_constraints(table: NEW_NAME, from: OLD_NAME, to: NEW_NAME)
  end

  def down
    # Rename the constraints while the table still exists under its current
    # name, then rename the table. The other order would target a relation that
    # does not exist yet.
    rename_constraints(table: NEW_NAME, from: NEW_NAME, to: OLD_NAME)
    rename_table NEW_NAME.to_sym, OLD_NAME.to_sym
  end

  private

  # `rename_table` renames the table, its sequence, and its generated indexes,
  # but not its constraints. Both the hand-written check constraints and the
  # NOT NULL constraints that PostgreSQL 18 catalogs by name keep the old
  # prefix, so rename every constraint whose name carries it.
  #
  # The prefix is discovered rather than hard-coded: a literal list silently
  # misses the generated `*_not_null` names and would leave a migrated database
  # diverging from a schema-loaded one.
  #
  # The primary key is deliberately excluded. `rename_table` renames it and its
  # backing index itself, and renaming it here first makes that step fail.
  def rename_constraints(table:, from:, to:)
    prefix = "#{from}_"

    constraint_names(table)
      .select { it.start_with?(prefix) }
      .each do |name|
        execute <<~SQL.squish
          ALTER TABLE #{connection.quote_table_name(table)}
          RENAME CONSTRAINT #{connection.quote_column_name(name)}
          TO #{connection.quote_column_name("#{to}_#{name.delete_prefix(prefix)}")}
        SQL
      end
  end

  def constraint_names(table)
    connection.select_values(<<~SQL.squish)
      SELECT conname
      FROM pg_constraint
      WHERE conrelid = #{connection.quote(table)}::regclass
        AND contype <> 'p'
      ORDER BY conname
    SQL
  end
end
