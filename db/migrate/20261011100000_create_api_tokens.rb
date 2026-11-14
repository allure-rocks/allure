# frozen_string_literal: true

# PLAN_API.md §4.1: personal API tokens. Only a SHA-256 digest of the secret
# is stored; the prefix identifies a token in lists without revealing it.
class CreateApiTokens < ActiveRecord::Migration[8.1]
  SCOPES = %w[read write import publish social:read webhooks].freeze

  def change
    create_table :api_tokens do |t|
      t.uuid :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.string :token_prefix, null: false
      t.string :token_digest, null: false
      t.string :scopes, array: true, null: false, default: []
      t.datetime :expires_at, null: false
      t.datetime :last_used_at
      t.datetime :revoked_at
      t.string :revoked_by
      t.timestamps

      t.index :uuid, unique: true
      t.index :token_digest, unique: true
      t.index %i[user_id revoked_at]
    end

    add_check_constraint :api_tokens, "char_length(name) BETWEEN 1 AND 80", name: "api_tokens_name_length"
    add_check_constraint :api_tokens, "token_digest ~ '^[0-9a-f]{64}$'", name: "api_tokens_digest_format"
    add_check_constraint :api_tokens, "cardinality(scopes) > 0 AND scopes <@ ARRAY[#{SCOPES.map { "'#{_1}'" }.join(", ")}]::varchar[]",
                         name: "api_tokens_scopes"
    add_check_constraint :api_tokens, "expires_at <= created_at + interval '366 days'", name: "api_tokens_expiry"
    add_check_constraint :api_tokens,
                         "(revoked_at IS NULL AND revoked_by IS NULL) OR " \
                         "(revoked_at IS NOT NULL AND revoked_by IN ('owner', 'operator', 'system'))",
                         name: "api_tokens_revocation"
  end
end
