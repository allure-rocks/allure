# frozen_string_literal: true

# docs/dev/DERIVATIONS.md: every segment, route and loop carries an owner route
# image rendered on the dedicated route_images worker, and records the renderer
# generation that produced it. Zero means missing or stale, so the rebuild
# sweeps re-render incrementally instead of redoing the whole library. The
# migration-time value is 1, the first renderer generation.
class AddRouteImageVersionToSegments < ActiveRecord::Migration[8.1]
  def change
    add_column :segments, :route_image_version, :integer, default: 0, null: false
    add_check_constraint :segments, "route_image_version >= 0", name: "segments_route_image_version"
    add_index :segments, [ :route_image_version, :id ]
  end
end
