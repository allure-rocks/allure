# frozen_string_literal: true

# A loop the owner renamed is a manual course, not derived data: it is marked
# with the rename time, elected by the reconciliation and spared by the orphan
# sweep (docs/dev/SEGMENTS.md). The mark is only ever set by an explicit
# rename — existing rows are deliberately left unmarked, because a stored
# name cannot tell an auto-generated "<title> loop" from an owner's choice.
class AddRenamedAtToSegments < ActiveRecord::Migration[8.1]
  def change
    add_column :segments, :renamed_at, :datetime, if_not_exists: true
  end
end
