class CreateRemoteSegments < ActiveRecord::Migration[8.1]
  def change
    create_table :remote_segments do |t|
      t.bigint :actor_id, null: false
      t.text :object_uri, null: false
      t.text :activity_uri, null: false
      t.string :status, null: false, default: "active"
      t.string :audience, null: false, default: "public"
      t.string :name, null: false
      t.text :description
      t.text :content_html
      t.string :sport_label
      t.string :kind, null: false, default: "segment"
      t.decimal :distance, precision: 14, scale: 3
      t.decimal :ascent, precision: 12, scale: 2
      t.decimal :descent, precision: 12, scale: 2
      t.decimal :average_grade, precision: 5, scale: 2
      t.datetime :published_at, null: false
      t.datetime :received_at, null: false
      t.datetime :deleted_at
      t.string :source_domain, null: false
      t.jsonb :representation, null: false, default: {}
      t.jsonb :route_metadata, null: false, default: {}
      t.jsonb :raw, null: false, default: {}
      t.jsonb :warnings, null: false, default: []
      t.datetime :location_data_purged_at
      t.timestamps
    end

    add_index :remote_segments, :object_uri, unique: true
    add_index :remote_segments, [ :actor_id, :published_at ]
    add_index :remote_segments, [ :source_domain, :status ]
    add_index :remote_segments, [ :status, :published_at ]
    add_index :remote_segments, [ :status, :updated_at ],
              where: "status = 'deleted' AND location_data_purged_at IS NULL",
              name: "index_remote_segments_on_cleanup"

    add_foreign_key :remote_segments, :actors

    add_check_constraint :remote_segments,
                         "status IN ('active', 'deleted')",
                         name: "remote_segments_status"
    add_check_constraint :remote_segments,
                         "audience IN ('public', 'followers')",
                         name: "remote_segments_audience"
    add_check_constraint :remote_segments,
                         "(status = 'deleted') = (deleted_at IS NOT NULL)",
                         name: "remote_segments_deletion_state"
    add_check_constraint :remote_segments,
                         "char_length(object_uri) > 0 AND char_length(activity_uri) > 0",
                         name: "remote_segments_uris"
    add_check_constraint :remote_segments,
                         "char_length(source_domain) > 0",
                         name: "remote_segments_source_domain"
    add_check_constraint :remote_segments,
                         "char_length(name) <= 120",
                         name: "remote_segments_name_length"
    add_check_constraint :remote_segments,
                         "kind = 'segment'",
                         name: "remote_segments_kind"
    add_check_constraint :remote_segments,
                         "distance IS NULL OR distance > 0",
                         name: "remote_segments_distance"
    add_check_constraint :remote_segments,
                         "(ascent IS NULL OR ascent >= 0) AND (descent IS NULL OR descent >= 0)",
                         name: "remote_segments_elevation"
    add_check_constraint :remote_segments,
                         "average_grade IS NULL OR (average_grade >= -100 AND average_grade <= 100)",
                         name: "remote_segments_average_grade"
    %w[representation route_metadata raw].each do |column|
      add_check_constraint :remote_segments,
                           "jsonb_typeof(#{column}) = 'object'",
                           name: "remote_segments_#{column}_object"
    end
    add_check_constraint :remote_segments,
                         "jsonb_typeof(warnings) = 'array'",
                         name: "remote_segments_warnings_array"
  end
end
