class CreateRemoteNotes < ActiveRecord::Migration[8.1]
  def change
    create_table :remote_notes do |t|
      t.bigint :actor_id, null: false
      t.text :object_uri, null: false
      t.text :activity_uri, null: false
      t.string :status, null: false, default: "active"
      t.text :title
      t.text :description
      t.text :content_html
      t.string :sport_label
      t.datetime :started_at
      t.datetime :published_at
      t.datetime :received_at, null: false
      t.datetime :deleted_at
      t.string :source_domain, null: false
      t.jsonb :metrics, null: false, default: {}
      t.jsonb :representation, null: false, default: {}
      t.jsonb :route_metadata, null: false, default: {}
      t.jsonb :raw, null: false, default: {}
      t.jsonb :warnings, null: false, default: []
      t.datetime :location_data_purged_at
      t.timestamps
    end

    add_index :remote_notes, :object_uri, unique: true
    add_index :remote_notes, [ :actor_id, :published_at ]
    add_index :remote_notes, [ :source_domain, :status ]
    add_index :remote_notes, [ :status, :published_at ]
    add_index :remote_notes, [ :status, :updated_at ],
              where: "status = 'deleted' AND location_data_purged_at IS NULL",
              name: "index_remote_notes_on_cleanup"

    add_foreign_key :remote_notes, :actors
    add_check_constraint :remote_notes,
                         "status IN ('active', 'deleted')",
                         name: "remote_notes_status"
    add_check_constraint :remote_notes,
                         "(status = 'deleted') = (deleted_at IS NOT NULL)",
                         name: "remote_notes_deletion_state"
    add_check_constraint :remote_notes,
                         "char_length(object_uri) > 0 AND char_length(activity_uri) > 0",
                         name: "remote_notes_uris"
    add_check_constraint :remote_notes,
                         "char_length(source_domain) > 0",
                         name: "remote_notes_source_domain"
    %w[metrics representation route_metadata raw].each do |column|
      add_check_constraint :remote_notes,
                           "jsonb_typeof(#{column}) = 'object'",
                           name: "remote_notes_#{column}_object"
    end
    add_check_constraint :remote_notes,
                         "jsonb_typeof(warnings) = 'array'",
                         name: "remote_notes_warnings_array"
  end
end
