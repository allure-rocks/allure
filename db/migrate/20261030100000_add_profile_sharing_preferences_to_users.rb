class AddProfileSharingPreferencesToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :share_profile_statistics, :boolean, default: false, null: false
    add_column :users, :share_profile_records, :boolean, default: false, null: false
  end
end
