class AddSegmentPublicationOutboxSubject < ActiveRecord::Migration[8.1]
  def up
    add_reference :federation_outbox_events,
                  :segment_publication,
                  null: true,
                  foreign_key: { to_table: :segment_publications },
                  index: false

    add_index :federation_outbox_events,
              [ :segment_publication_id, :status ],
              name: "index_outbox_events_on_segment_publication_and_status"

    remove_check_constraint :federation_outbox_events, name: "outbox_subject_type"
    remove_check_constraint :federation_outbox_events, name: "outbox_publication_subject_integrity"

    add_check_constraint :federation_outbox_events,
                         "subject_type IN ('WorkoutPublication', 'SegmentPublication', 'Actor')",
                         name: "outbox_subject_type"
    add_check_constraint :federation_outbox_events,
                         "(subject_type = 'WorkoutPublication' AND workout_publication_id IS NOT NULL AND subject_id = workout_publication_id AND segment_publication_id IS NULL) OR " \
                         "(subject_type = 'SegmentPublication' AND segment_publication_id IS NOT NULL AND subject_id = segment_publication_id AND workout_publication_id IS NULL) OR " \
                         "(subject_type = 'Actor' AND workout_publication_id IS NULL AND segment_publication_id IS NULL)",
                         name: "outbox_publication_subject_integrity"
  end

  def down
    remove_check_constraint :federation_outbox_events, name: "outbox_publication_subject_integrity"
    remove_check_constraint :federation_outbox_events, name: "outbox_subject_type"

    add_check_constraint :federation_outbox_events,
                         "subject_type IN ('WorkoutPublication', 'Actor')",
                         name: "outbox_subject_type"
    add_check_constraint :federation_outbox_events,
                         "(subject_type = 'WorkoutPublication' AND workout_publication_id IS NOT NULL AND subject_id = workout_publication_id) OR (subject_type = 'Actor' AND workout_publication_id IS NULL)",
                         name: "outbox_publication_subject_integrity"
    remove_index :federation_outbox_events, name: "index_outbox_events_on_segment_publication_and_status"
    remove_reference :federation_outbox_events, :segment_publication, foreign_key: { to_table: :segment_publications }
  end
end
