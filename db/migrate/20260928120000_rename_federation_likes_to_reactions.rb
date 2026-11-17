# frozen_string_literal: true

# Reactions generalize the M2 FederationLike state (docs/dev/REACTIONS.md): one
# table holds inbound ActivityPub Likes, outbound local appreciations of
# received notes, and purely local reactions to local publications, each with
# one of four types. `undone_at` keeps the withdrawal history; one active
# reaction per actor and target stays enforced by partial unique indexes.
class RenameFederationLikesToReactions < ActiveRecord::Migration[8.1]
  def change
    # `rename_table` already renames the indexes named after the table; only
    # the custom partial-index name needs an explicit rename.
    rename_table :federation_likes, :reactions
    rename_index :reactions, "index_active_likes_on_actor_and_workout",
                 "index_active_reactions_on_actor_and_workout"

    # Existing rows are inbound generic Likes: they keep their neutral type.
    add_column :reactions, :kind, :string, null: false, default: "like"
    add_column :reactions, :remote_note_id, :bigint
    change_column_null :reactions, :workout_id, true

    add_index :reactions, [ :actor_id, :remote_note_id ], unique: true,
              where: "undone_at IS NULL AND remote_note_id IS NOT NULL",
              name: "index_active_reactions_on_actor_and_remote_note"
    add_foreign_key :reactions, :remote_notes, on_delete: :cascade

    add_check_constraint :reactions,
                         "kind IN ('beer', 'energy', 'coffee', 'like')",
                         name: "reactions_kind"
    add_check_constraint :reactions,
                         "((workout_id IS NOT NULL)::int + (remote_note_id IS NOT NULL)::int) = 1",
                         name: "reactions_single_target"
  end
end
