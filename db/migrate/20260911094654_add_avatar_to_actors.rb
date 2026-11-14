class AddAvatarToActors < ActiveRecord::Migration[8.1]
  def change
    add_column :actors, :avatar_url, :text
    add_column :actors, :avatar_cached_at, :datetime
  end
end
