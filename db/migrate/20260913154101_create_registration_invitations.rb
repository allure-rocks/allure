class CreateRegistrationInvitations < ActiveRecord::Migration[8.1]
  def change
    create_table :registration_invitations do |t|
      t.string :token_digest, null: false
      t.string :email_address, null: false
      t.datetime :expires_at, null: false
      t.datetime :accepted_at
      t.timestamps
    end

    add_index :registration_invitations, :token_digest, unique: true
    add_index :registration_invitations, :email_address
  end
end
