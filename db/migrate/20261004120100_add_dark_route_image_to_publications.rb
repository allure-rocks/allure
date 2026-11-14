# frozen_string_literal: true

# The dark variant of the sanitized route-image snapshot. Publications keep
# both variants and reference each blob once, like the light image; federation
# advertises them together (DESIGN.md §15.4, PLAN_M5.md §8).
class AddDarkRouteImageToPublications < ActiveRecord::Migration[8.1]
  def change
    %i[workout_publications segment_publications].each do |table|
      add_column table, :sanitized_route_image_dark_blob_id, :bigint
      add_index table, :sanitized_route_image_dark_blob_id
      add_foreign_key table, :active_storage_blobs, column: :sanitized_route_image_dark_blob_id
    end
  end
end
