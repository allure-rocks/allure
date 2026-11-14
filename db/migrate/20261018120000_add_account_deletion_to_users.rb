class AddAccountDeletionToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :deletion_requested_at, :datetime
    add_column :users, :deletion_scheduled_at, :datetime
    add_column :users, :deletion_requested_by, :string
    add_column :users, :deletion_started_at, :datetime
    add_index :users, :deletion_scheduled_at, where: "deletion_scheduled_at IS NOT NULL"
    add_check_constraint :users,
                         "(deletion_requested_at IS NULL AND deletion_scheduled_at IS NULL AND deletion_requested_by IS NULL) " \
                         "OR (deletion_requested_at IS NOT NULL AND deletion_scheduled_at IS NOT NULL " \
                         "AND deletion_requested_by IN ('self', 'operator'))",
                         name: "users_deletion_request"
    add_check_constraint :users,
                         "deletion_started_at IS NULL OR deletion_scheduled_at IS NOT NULL",
                         name: "users_deletion_started"
  end
end
