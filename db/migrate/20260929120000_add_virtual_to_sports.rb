# frozen_string_literal: true

# PLAN_VIRTUAL.md: a virtual sport records an activity that happened in a
# rendered world, not on a real route. The flag drives what the pipeline must
# not do (geocoding) and which platforms a workout may be located in.
class AddVirtualToSports < ActiveRecord::Migration[8.1]
  def change
    add_column :sports, :virtual, :boolean, default: false, null: false
  end
end
