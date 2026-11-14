class AddAcctToActors < ActiveRecord::Migration[8.1]
  def up
    add_column :actors, :acct, :string

    # The stored handle predates the port-aware acct. Existing remote rows can
    # only be backfilled with the handle value; the next actor resolution
    # replaces it with the exact WebFinger account.
    execute <<~SQL.squish
      UPDATE actors
      SET acct = handle
      WHERE acct IS NULL AND handle IS NOT NULL
    SQL

    add_index :actors, :acct
  end

  def down
    remove_index :actors, :acct
    remove_column :actors, :acct
  end
end
