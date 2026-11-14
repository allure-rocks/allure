# frozen_string_literal: true

# PLAN_API.md §5: the REST API names a publishing profile by a ShortUUID, never
# by its bigint key. The web keeps its existing routes.
class AddUuidToPublishingProfiles < ActiveRecord::Migration[8.1]
  def change
    add_column :publishing_profiles, :uuid, :uuid, null: false, default: -> { "gen_random_uuid()" }
    add_index :publishing_profiles, :uuid, unique: true
  end
end
