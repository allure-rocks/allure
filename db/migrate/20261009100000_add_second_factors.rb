# frozen_string_literal: true

# Second factors (docs/dev/AUTH.md): authenticator codes on the account,
# passkeys and recovery codes in their own tables, and the session state that
# records which factor was proved and whether the session may only enrol.
#
# Every existing account holds a password, so its second-factor obligation
# starts now and its grace period with it.
class AddSecondFactors < ActiveRecord::Migration[8.1]
  def change
    change_table :users, bulk: true do |t|
      t.text :otp_secret
      t.bigint :otp_last_used_step
      t.datetime :otp_enrolled_at
      t.datetime :second_factor_required_since
      t.string :webauthn_id
    end
    add_index :users, :webauthn_id, unique: true, where: "webauthn_id IS NOT NULL"
    add_check_constraint :users, "(otp_secret IS NULL) = (otp_enrolled_at IS NULL)", name: "users_otp_enrolment"

    reversible do |direction|
      direction.up do
        execute "UPDATE users SET second_factor_required_since = CURRENT_TIMESTAMP WHERE password_digest IS NOT NULL"
      end
    end

    create_table :webauthn_credentials do |t|
      t.references :user, null: false, foreign_key: true
      t.string :external_id, null: false
      t.text :public_key, null: false
      t.bigint :sign_count, null: false, default: 0
      t.string :nickname, null: false
      t.string :transports, array: true, null: false, default: []
      t.boolean :backed_up, null: false, default: false
      t.datetime :last_used_at
      t.timestamps
    end
    add_index :webauthn_credentials, :external_id, unique: true
    add_check_constraint :webauthn_credentials, "sign_count >= 0", name: "webauthn_credentials_sign_count"
    add_check_constraint :webauthn_credentials, "char_length(nickname) BETWEEN 1 AND 60",
                         name: "webauthn_credentials_nickname"

    create_table :recovery_codes do |t|
      t.references :user, null: false, foreign_key: true
      t.string :code_digest, null: false
      t.datetime :used_at
      t.datetime :created_at, null: false
    end
    add_index :recovery_codes, :code_digest, unique: true

    change_table :sessions, bulk: true do |t|
      t.string :second_factor_method
      t.datetime :second_factor_at
      t.boolean :enrolment_only, null: false, default: false
    end
    add_check_constraint :sessions,
                         "second_factor_method IS NULL OR second_factor_method IN ('totp', 'webauthn', 'recovery_code')",
                         name: "sessions_second_factor_method"
    add_check_constraint :sessions, "(second_factor_method IS NULL) = (second_factor_at IS NULL)",
                         name: "sessions_second_factor_state"
  end
end
