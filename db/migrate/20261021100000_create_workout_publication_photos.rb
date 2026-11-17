# frozen_string_literal: true

# The photos a publication froze (docs/dev/PHOTOS.md): independent,
# metadata-free copies made at publish time, immutable, purged with the
# publication's other media when it is withdrawn. The shared distance is
# measured along the published route, never a coordinate.
class CreateWorkoutPublicationPhotos < ActiveRecord::Migration[8.1]
  def change
    create_table :workout_publication_photos do |t|
      t.uuid :uuid, null: false, default: -> { "gen_random_uuid()" }, index: { unique: true }
      t.references :workout_publication, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.integer :position, null: false
      t.integer :width, null: false
      t.integer :height, null: false
      t.text :caption
      t.float :distance
      t.datetime :created_at, null: false

      t.index %i[workout_publication_id position], unique: true, name: "index_workout_publication_photos_on_position"
      t.check_constraint "position >= 0 AND position < 20", name: "workout_publication_photos_position"
      t.check_constraint "width > 0 AND height > 0", name: "workout_publication_photos_dimensions"
      t.check_constraint "caption IS NULL OR char_length(caption) <= 500", name: "workout_publication_photos_caption_length"
      t.check_constraint "distance IS NULL OR distance >= 0", name: "workout_publication_photos_distance"
    end
  end
end
