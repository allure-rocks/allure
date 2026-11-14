# frozen_string_literal: true

class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :email_address, null: false
      t.string :password_digest, null: false

      # The username is the local part of the fediverse handle (@username@domain)
      # and appears in the actor URI, which is permanent once federated. It is
      # therefore treated as an identifier, not a display field: immutable in
      # practice, and unique case-insensitively so that @Marie and @marie can
      # never resolve to two different actors.
      t.string :username, null: false

      t.string :display_name
      t.text :bio

      t.string :locale, null: false, default: "fr"
      t.string :theme, null: false, default: "light"
      t.string :time_zone, null: false, default: "Europe/Paris"
      t.string :unit_system, null: false, default: "metric"

      t.timestamps
    end

    add_index :users, :email_address, unique: true
    add_index :users, "lower(username)", unique: true, name: "index_users_on_lower_username"

    # Usernames end up in URIs and in WebFinger subjects. Constrain the shape at
    # the database level so no code path can create an actor that is unroutable
    # or ambiguous to remote implementations.
    #
    # NOTE: PostgreSQL's ARE engine supports \A and \Z but *not* lowercase \z,
    # which Ruby uses. Getting this wrong is quiet — the constraint is created
    # happily and only raises on the first INSERT.
    add_check_constraint :users,
                         "username ~ '\\A[a-zA-Z0-9_]{1,30}\\Z'",
                         name: "users_username_format"
  end
end
