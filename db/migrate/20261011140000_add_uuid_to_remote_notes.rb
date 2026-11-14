# frozen_string_literal: true

# PLAN_API.md §5: the REST API names a received note by a ShortUUID, never by
# its bigint key. The web keeps its existing /remote_notes/:id routes.
class AddUuidToRemoteNotes < ActiveRecord::Migration[8.1]
  def change
    add_column :remote_notes, :uuid, :uuid, null: false, default: -> { "gen_random_uuid()" }
    add_index :remote_notes, :uuid, unique: true
  end
end
