# frozen_string_literal: true

class AddProfileSharingAudiencesToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :profile_statistics_audience, :string, default: "none", null: false
    add_column :users, :profile_records_audience, :string, default: "none", null: false
    add_check_constraint :users, "profile_statistics_audience IN ('none', 'followers', 'members')", name: "users_profile_statistics_audience"
    add_check_constraint :users, "profile_records_audience IN ('none', 'followers', 'members')", name: "users_profile_records_audience"

    execute <<~SQL
      UPDATE users SET
        profile_statistics_audience = CASE WHEN share_profile_statistics THEN 'members' ELSE 'none' END,
        profile_records_audience = CASE WHEN share_profile_records THEN 'members' ELSE 'none' END
    SQL
    remove_columns :users, :share_profile_statistics, :share_profile_records
  end

  def down
    # A boolean cannot retain a followers audience. Refuse to discard that
    # choice rather than silently making it visible to every instance member.
    if select_value("SELECT EXISTS (SELECT 1 FROM users WHERE profile_statistics_audience = 'followers' OR profile_records_audience = 'followers')")
      raise ActiveRecord::IrreversibleMigration, "choose none or members for every profile-sharing audience before rollback"
    end

    add_column :users, :share_profile_statistics, :boolean, default: false, null: false
    add_column :users, :share_profile_records, :boolean, default: false, null: false
    execute <<~SQL
      UPDATE users SET
        share_profile_statistics = (profile_statistics_audience = 'members'),
        share_profile_records = (profile_records_audience = 'members')
    SQL
    remove_columns :users, :profile_statistics_audience, :profile_records_audience
  end
end
