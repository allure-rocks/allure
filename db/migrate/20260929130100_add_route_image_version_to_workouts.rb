# frozen_string_literal: true

# docs/dev/DERIVATIONS.md: the owner route image records the renderer generation
# that produced it. Zero means missing or stale (the geometry was replaced by a
# re-analysis), so a rebuild sweep can re-render incrementally instead of
# redoing the whole library.
#
# Migration-time value 1 is the first renderer generation. Every image already
# attached was produced by that renderer, so it is stamped current here; a
# later bump of Workouts::RouteImage::VERSION makes them stale again.
class AddRouteImageVersionToWorkouts < ActiveRecord::Migration[8.1]
  RENDERER_VERSION = 1

  def change
    add_column :workouts, :route_image_version, :integer, default: 0, null: false
    add_check_constraint :workouts, "route_image_version >= 0", name: "workouts_route_image_version"
    add_index :workouts, [ :route_image_version, :id ]

    reversible do |direction|
      direction.up do
        execute <<~SQL
          UPDATE workouts
          SET route_image_version = #{RENDERER_VERSION}
          WHERE id IN (
            SELECT record_id FROM active_storage_attachments
            WHERE record_type = 'Workout' AND name = 'route_image'
          )
        SQL
      end
    end
  end
end
