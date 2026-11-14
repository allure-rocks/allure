# frozen_string_literal: true

# PLAN_AUTH.md §4.6 and §9: the iOS companion signs in through a provider in
# the system browser, which hands the verified answer back to the app's web
# view through a single-use, short-lived token bound to a PKCE challenge.
class CreateSessionHandoffs < ActiveRecord::Migration[8.1]
  def change
    create_table :session_handoffs do |t|
      t.string :token_digest, null: false
      t.string :code_challenge, null: false
      t.text :payload, null: false
      t.datetime :expires_at, null: false
      t.timestamps
    end

    add_index :session_handoffs, :token_digest, unique: true
    add_index :session_handoffs, :expires_at
    add_check_constraint :session_handoffs, "char_length(code_challenge) = 43", name: "session_handoffs_code_challenge"
  end
end
