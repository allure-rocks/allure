class CreateSegments < ActiveRecord::Migration[8.1]
  def change
    create_table :segments do |t|
      t.uuid :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.references :user, null: false, foreign_key: true, index: false
      t.references :sport, null: true, foreign_key: true, index: false

      t.string :kind, null: false
      t.string :name, null: false
      t.text :description

      t.line_string :geom, geographic: true, null: false
      t.st_point :start_point, geographic: true, null: false
      t.st_point :end_point, geographic: true, null: false
      t.float :bounds, array: true, null: false

      t.decimal :distance, precision: 14, scale: 3, null: false
      t.decimal :ascent, precision: 12, scale: 2
      t.decimal :descent, precision: 12, scale: 2
      t.decimal :min_elevation, precision: 10, scale: 2
      t.decimal :max_elevation, precision: 10, scale: 2
      t.decimal :average_grade, precision: 5, scale: 2
      t.column :signature, :real, array: true, null: false

      t.integer :match_tolerance_meters, null: false, default: 25
      t.string :visibility, null: false, default: "private"
      t.string :leaderboard_audience, null: false, default: "owner"

      t.references :source_workout, null: true, foreign_key: { to_table: :workouts, on_delete: :nullify }, index: false
      t.integer :source_start_index
      t.integer :source_end_index

      t.boolean :active, null: false, default: true
      t.integer :efforts_count, null: false, default: 0
      t.integer :athletes_count, null: false, default: 0
      t.integer :matcher_version, null: false

      t.timestamps
    end

    add_index :segments, :uuid, unique: true
    add_index :segments, [ :user_id, :kind ]
    add_index :segments, [ :visibility, :kind ]
    add_index :segments, :geom, using: :gist
    add_index :segments, :start_point, using: :gist
    add_index :segments, :end_point, using: :gist

    add_check_constraint :segments,
                         "kind IN ('segment', 'route', 'loop')",
                         name: "segments_kind"
    add_check_constraint :segments,
                         "visibility IN ('public', 'followers_only', 'private')",
                         name: "segments_visibility"
    add_check_constraint :segments,
                         "leaderboard_audience IN ('owner', 'members', 'followers', 'public')",
                         name: "segments_leaderboard_audience"
    add_check_constraint :segments, "distance > 0", name: "segments_distance"
    add_check_constraint :segments, "cardinality(bounds) = 4", name: "segments_bounds"
    add_check_constraint :segments, "cardinality(signature) = 64", name: "segments_signature"
    add_check_constraint :segments,
                         "match_tolerance_meters BETWEEN 5 AND 100",
                         name: "segments_match_tolerance_meters"
    add_check_constraint :segments,
                         "ST_NPoints(geom::geometry) >= 2",
                         name: "segments_geometry"
    add_check_constraint :segments,
                         "char_length(name) BETWEEN 1 AND 120",
                         name: "segments_name_length"
    add_check_constraint :segments,
                         "description IS NULL OR char_length(description) <= 2000",
                         name: "segments_description_length"
    add_check_constraint :segments,
                         "ascent IS NULL OR ascent >= 0",
                         name: "segments_ascent"
    add_check_constraint :segments,
                         "descent IS NULL OR descent >= 0",
                         name: "segments_descent"
    add_check_constraint :segments,
                         "efforts_count >= 0 AND athletes_count >= 0",
                         name: "segments_counts"
  end
end
