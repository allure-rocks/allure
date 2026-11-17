# frozen_string_literal: true

# Identity providers (docs/dev/AUTH.md): an account may sign in through
# a linked provider identity, keyed by its issuer and subject only, and may
# then have no password at all. Each session records how it signed in.
class CreateIdentities < ActiveRecord::Migration[8.1]
  def change
    create_table :identities do |t|
      t.references :user, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :issuer, null: false
      t.string :subject, null: false
      t.string :email
      t.boolean :email_verified, null: false, default: false
      t.datetime :linked_at, null: false
      t.datetime :last_used_at
      t.timestamps
    end
    add_index :identities, %i[issuer subject], unique: true
    add_index :identities, %i[user_id provider], unique: true
    add_check_constraint :identities, "provider IN ('google', 'apple', 'oidc')", name: "identities_provider"
    add_check_constraint :identities, "char_length(issuer) > 0 AND char_length(subject) > 0",
                         name: "identities_issuer_subject"

    change_column_null :users, :password_digest, true

    add_column :sessions, :auth_method, :string, null: false, default: "password"
    add_check_constraint :sessions, "auth_method IN ('password', 'provider:google', 'provider:apple', 'provider:oidc')",
                         name: "sessions_auth_method"
  end
end
