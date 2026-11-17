# frozen_string_literal: true

# docs/dev/SHARED-ACTIVITIES.md: a local owner invites a remote Allure
# account through an outbound `Invite`, and an invited local account keeps
# the invitation it received as a `RemoteParticipation`.
#
# - the outbox admits `Invite`;
# - an owner's participation remembers the publication its invitation rides
#   on, so a withdrawal or a replacement can tell what was offered;
# - `remote_participations` is the receiving side: one live row per local
#   account and publication, a refusal terminal, a withdrawal freeing it.
class CreateRemoteParticipations < ActiveRecord::Migration[8.1]
  PREVIOUS_TYPES = %w[Create Delete Undo Follow Accept Reject Like Announce].freeze

  def up
    replace_activity_types(PREVIOUS_TYPES + [ "Invite" ])

    add_reference :workout_participations, :workout_publication,
                  foreign_key: { on_delete: :nullify }

    create_table :remote_participations do |t|
      t.uuid :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.references :remote_note, null: false, foreign_key: { on_delete: :cascade }
      t.references :recipient_actor, null: false, foreign_key: { to_table: :actors, on_delete: :restrict }
      t.text :object_uri, null: false
      t.text :invite_activity_uri, null: false
      t.string :sport_slug, limit: 64
      t.datetime :started_at
      t.datetime :confirmed_at
      t.datetime :declined_at
      t.datetime :withdrawn_at
      t.timestamps
    end

    add_index :remote_participations, :uuid, unique: true
    add_index :remote_participations, :invite_activity_uri, unique: true
    # One pending, confirmed, or declined invitation per account and
    # publication; a refusal stays live so it stays the last word, and only a
    # withdrawal frees the pair for a fresh invitation.
    add_index :remote_participations, %i[recipient_actor_id object_uri],
              unique: true, where: "withdrawn_at IS NULL", name: "index_remote_participations_live_pair"
    add_check_constraint :remote_participations, "NOT (confirmed_at IS NOT NULL AND declined_at IS NOT NULL)",
                         name: "remote_participations_one_answer"
  end

  def down
    drop_table :remote_participations
    remove_reference :workout_participations, :workout_publication, foreign_key: true
    execute "DELETE FROM federation_outbox_events WHERE activity_type = 'Invite'"
    replace_activity_types(PREVIOUS_TYPES)
  end

  private

  def replace_activity_types(types)
    remove_check_constraint :federation_outbox_events, name: "outbox_activity_type"
    add_check_constraint :federation_outbox_events, "activity_type IN (#{types.map { "'#{it}'" }.join(', ')})",
                         name: "outbox_activity_type"
  end
end
