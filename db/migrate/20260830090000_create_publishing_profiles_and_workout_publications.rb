# frozen_string_literal: true

class CreatePublishingProfilesAndWorkoutPublications < ActiveRecord::Migration[8.1]
  def change
    create_table :publishing_profiles do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.string :name, null: false
      t.string :built_in_key
      t.string :audience, null: false
      t.jsonb :settings, null: false, default: {}
      t.integer :position, null: false, default: 0

      t.timestamps
    end

    add_index :publishing_profiles, [ :user_id, :position ], name: "index_publishing_profiles_on_user_and_position"
    add_index :publishing_profiles,
              [ :user_id, :built_in_key ],
              unique: true,
              where: "built_in_key IS NOT NULL",
              name: "index_publishing_profiles_on_user_and_built_in_key"
    add_check_constraint :publishing_profiles,
                         "audience IN ('public', 'followers')",
                         name: "publishing_profiles_audience"
    add_check_constraint :publishing_profiles,
                         "built_in_key IS NULL OR (built_in_key IN ('public', 'followers') AND built_in_key = audience)",
                         name: "publishing_profiles_built_in_key"
    add_check_constraint :publishing_profiles,
                         "position >= 0",
                         name: "publishing_profiles_position"
    add_check_constraint :publishing_profiles,
                         "char_length(name) BETWEEN 1 AND 120",
                         name: "publishing_profiles_name_length"
    add_check_constraint :publishing_profiles,
                         "jsonb_typeof(settings) = 'object'",
                         name: "publishing_profiles_settings_object"

    create_table :workout_publications do |t|
      t.uuid :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.references :workout, null: false, foreign_key: true, index: false
      t.references :publishing_profile,
                   null: true,
                   foreign_key: { on_delete: :nullify },
                   index: false
      t.string :status, null: false, default: "active"
      t.text :object_uri, null: false
      t.jsonb :profile_snapshot, null: false, default: {}
      t.string :privacy_zone_fingerprint, null: false
      t.jsonb :route_metadata, null: false, default: {}
      t.integer :filtered_points_count, null: false, default: 0
      t.boolean :has_route, null: false, default: false
      t.datetime :published_at, null: false
      t.datetime :deleted_at

      t.timestamps
    end

    add_index :workout_publications, :uuid, unique: true
    add_index :workout_publications, :object_uri, unique: true
    add_index :workout_publications, :publishing_profile_id
    add_index :workout_publications,
              :workout_id,
              unique: true,
              where: "status = 'active'",
              name: "index_active_workout_publications_on_workout_id"
    add_check_constraint :workout_publications,
                         "status IN ('active', 'deleted')",
                         name: "workout_publications_status"
    add_check_constraint :workout_publications,
                         "(status = 'active' AND deleted_at IS NULL) OR (status = 'deleted' AND deleted_at IS NOT NULL)",
                         name: "workout_publications_deletion_state"
    add_check_constraint :workout_publications,
                         "char_length(object_uri) > 0",
                         name: "workout_publications_object_uri"
    add_check_constraint :workout_publications,
                         "jsonb_typeof(profile_snapshot) = 'object'",
                         name: "workout_publications_profile_snapshot_object"
    add_check_constraint :workout_publications,
                         "privacy_zone_fingerprint ~ '^[0-9a-f]{64}$'",
                         name: "workout_publications_privacy_zone_fingerprint"
    add_check_constraint :workout_publications,
                         "jsonb_typeof(route_metadata) = 'object'",
                         name: "workout_publications_route_metadata_object"
    add_check_constraint :workout_publications,
                         "filtered_points_count >= 0",
                         name: "workout_publications_filtered_points_count"
  end
end
