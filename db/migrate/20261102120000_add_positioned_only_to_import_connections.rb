# frozen_string_literal: true

# PLAN_REMOTE_IMPORTS.md §7c.3: a Withings account fed by Apple Health lists
# auto-detected sessions (often without any recorded position) beside real
# workouts; the connection may import positioned sessions only. The flag is
# on for the existing Withings connections — the provider is not released
# yet — and set on creation for every provider with the `:route_filter`
# capability.
class AddPositionedOnlyToImportConnections < ActiveRecord::Migration[8.1]
  def up
    add_column :import_connections, :positioned_only, :boolean, default: false, null: false
    execute <<~SQL
      UPDATE import_connections SET positioned_only = true WHERE provider = 'withings'
    SQL
  end

  def down
    remove_column :import_connections, :positioned_only
  end
end
