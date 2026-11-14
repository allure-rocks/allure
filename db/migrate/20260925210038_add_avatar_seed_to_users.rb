# frozen_string_literal: true

class AddAvatarSeedToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :avatar_seed, :bigint
    execute "UPDATE users SET avatar_seed = floor(random() * 2147483647)::bigint WHERE avatar_seed IS NULL"
    change_column_null :users, :avatar_seed, false
  end

  def down
    remove_column :users, :avatar_seed
  end
end
