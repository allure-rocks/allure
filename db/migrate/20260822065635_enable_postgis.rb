# frozen_string_literal: true

# PostGIS is a hard requirement, not an optional feature: workout tracks are
# stored as geography(LineString, 4326) and start points as geography(Point, 4326).
#
# Enabling it in a migration (rather than relying on the adapter's create_database
# hook) means it is recorded in schema.rb, so every freshly loaded database —
# test, CI, a self-hoster's first boot — has it.
class EnablePostgis < ActiveRecord::Migration[8.1]
  def change
    enable_extension "postgis" unless extension_enabled?("postgis")
  end
end
