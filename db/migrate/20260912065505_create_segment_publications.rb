class CreateSegmentPublications < ActiveRecord::Migration[8.1]
  def change
    create_table :segment_publications do |t|
      t.bigint :actor_id, null: false
      t.bigint :segment_id
      t.text :object_uri, null: false
      t.string :audience, null: false
      t.jsonb :representation, default: {}, null: false
      t.jsonb :route_metadata, default: {}, null: false
      t.string :source_fingerprint, null: false
      t.string :status, default: "active", null: false
      t.datetime :published_at, null: false
      t.datetime :deleted_at
      t.datetime :location_data_purged_at
      t.bigint :sanitized_gpx_blob_id
      t.bigint :sanitized_route_image_blob_id
      t.uuid :uuid, default: -> { "gen_random_uuid()" }, null: false

      t.timestamps
    end

    add_index :segment_publications, :actor_id
    add_index :segment_publications, :object_uri, unique: true
    add_index :segment_publications, :uuid, unique: true
    add_index :segment_publications, :sanitized_gpx_blob_id
    add_index :segment_publications, :sanitized_route_image_blob_id
    add_index :segment_publications, [ :segment_id, :status ]
    add_index :segment_publications, :segment_id,
              name: "index_active_segment_publications_on_segment_id",
              unique: true, where: "status = 'active'"
    add_index :segment_publications, :updated_at,
              name: "index_segment_publications_on_cleanup",
              where: "status = 'deleted' AND location_data_purged_at IS NULL"

    add_foreign_key :segment_publications, :actors
    add_foreign_key :segment_publications, :segments, on_delete: :nullify
    add_foreign_key :segment_publications, :active_storage_blobs, column: :sanitized_gpx_blob_id
    add_foreign_key :segment_publications, :active_storage_blobs, column: :sanitized_route_image_blob_id

    add_check_constraint :segment_publications,
                         "char_length(object_uri) > 0",
                         name: "segment_publications_object_uri"
    add_check_constraint :segment_publications,
                         "source_fingerprint ~ '^[0-9a-f]{64}$'",
                         name: "segment_publications_source_fingerprint"
    add_check_constraint :segment_publications,
                         "jsonb_typeof(representation) = 'object'",
                         name: "segment_publications_representation_object"
    add_check_constraint :segment_publications,
                         "jsonb_typeof(route_metadata) = 'object'",
                         name: "segment_publications_route_metadata_object"
    add_check_constraint :segment_publications,
                         "status = 'active' AND deleted_at IS NULL OR status = 'deleted' AND deleted_at IS NOT NULL",
                         name: "segment_publications_deletion_state"
    add_check_constraint :segment_publications,
                         "status = 'deleted' OR segment_id IS NOT NULL",
                         name: "segment_publications_active_requires_source"
    add_check_constraint :segment_publications,
                         "status IN ('active', 'deleted')",
                         name: "segment_publications_status"
    add_check_constraint :segment_publications,
                         "audience IN ('public', 'followers')",
                         name: "segment_publications_audience"
  end
end
