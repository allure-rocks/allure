class AddExplicitPublicationOutboxSubject < ActiveRecord::Migration[8.1]
  def up
    add_reference :federation_outbox_events,
                  :workout_publication,
                  null: true,
                  foreign_key: { to_table: :workout_publications },
                  index: false

    execute <<~SQL
      UPDATE federation_outbox_events
      SET workout_publication_id = subject_id
      WHERE subject_type = 'WorkoutPublication'
        AND subject_id IS NOT NULL
        AND EXISTS (
          SELECT 1 FROM workout_publications WHERE workout_publications.id = subject_id
        )
    SQL

    add_index :federation_outbox_events,
              [ :workout_publication_id, :status ],
              name: "index_outbox_events_on_publication_and_status"
    add_check_constraint :federation_outbox_events,
                         "(subject_type = 'WorkoutPublication' AND workout_publication_id IS NOT NULL AND subject_id = workout_publication_id) OR (subject_type = 'Actor' AND workout_publication_id IS NULL)",
                         name: "outbox_publication_subject_integrity"
  end

  def down
    remove_check_constraint :federation_outbox_events, name: "outbox_publication_subject_integrity"
    remove_index :federation_outbox_events, name: "index_outbox_events_on_publication_and_status"
    remove_reference :federation_outbox_events, :workout_publication, foreign_key: { to_table: :workout_publications }
  end
end
