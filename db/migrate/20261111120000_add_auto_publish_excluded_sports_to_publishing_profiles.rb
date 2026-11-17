# frozen_string_literal: true

# docs/dev/AUTO-PUBLISHING.md: an automatic profile may leave sports out, as it
# leaves out commutes. Catalog slugs; the empty default excludes nothing, so
# every existing automatic profile keeps publishing every sport.
class AddAutoPublishExcludedSportsToPublishingProfiles < ActiveRecord::Migration[8.1]
  def change
    add_column :publishing_profiles, :auto_publish_excluded_sports, :string,
               array: true, default: [], null: false
  end
end
