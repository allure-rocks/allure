class AddPublicationCleanupAndRedactionState < ActiveRecord::Migration[8.1]
  def up
    add_column :workout_publications, :location_data_purged_at, :datetime, null: true
    add_column :federation_outbox_events, :payload_digest, :text, null: true
    add_column :federation_outbox_events, :payload_redacted_at, :datetime, null: true

    add_index :workout_publications,
              :updated_at,
              where: "status = 'deleted' AND location_data_purged_at IS NULL",
              name: "index_workout_publications_on_cleanup"
    add_index :federation_outbox_events,
              [ :status, :updated_at ],
              where: "status IN ('pending', 'expanded')",
              name: "index_outbox_events_on_recovery"
  end

  def down
    remove_index :federation_outbox_events, name: "index_outbox_events_on_recovery"
    remove_index :workout_publications, name: "index_workout_publications_on_cleanup"
    remove_column :federation_outbox_events, :payload_redacted_at
    remove_column :federation_outbox_events, :payload_digest
    remove_column :workout_publications, :location_data_purged_at
  end
end
