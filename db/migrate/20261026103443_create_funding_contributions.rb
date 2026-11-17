# frozen_string_literal: true

# docs/dev/FUNDING.md: voluntary, yearly contributions to the instance
# operator. Money stays at the payment provider; these rows only record the
# verified contribution and the honorific badge preferences.
class CreateFundingContributions < ActiveRecord::Migration[8.1]
  def change
    create_table :funding_contributions do |t|
      t.references :user, null: true, foreign_key: { on_delete: :cascade }
      t.string :provider, null: false
      t.string :tier, null: false
      t.string :external_id, null: false
      t.datetime :paid_at, null: false
      t.datetime :expires_at, null: false
      t.string :status, null: false, default: "active"
      t.bigint :amount_cents
      t.string :currency, limit: 3
      t.jsonb :metadata, null: false, default: {}
      t.timestamps

      t.index %i[provider external_id], unique: true
      t.index %i[user_id status expires_at], name: "index_funding_contributions_on_current_badges"
    end

    add_check_constraint :funding_contributions,
                         "provider ~ '\\A[a-z0-9_]+\\Z'",
                         name: "funding_contributions_provider_format"
    add_check_constraint :funding_contributions,
                         "tier IN ('coffee', 'beer', 'energy')",
                         name: "funding_contributions_tier"
    add_check_constraint :funding_contributions,
                         "length(btrim(external_id)) > 0",
                         name: "funding_contributions_external_id_present"
    add_check_constraint :funding_contributions,
                         "status IN ('active', 'revoked')",
                         name: "funding_contributions_status"
    add_check_constraint :funding_contributions,
                         "expires_at > paid_at",
                         name: "funding_contributions_period"
    add_check_constraint :funding_contributions,
                         "amount_cents IS NULL OR amount_cents >= 0",
                         name: "funding_contributions_amount_nonnegative"
    add_check_constraint :funding_contributions,
                         "currency IS NULL OR currency ~ '\\A[A-Z]{3}\\Z'",
                         name: "funding_contributions_currency_format"
    add_check_constraint :funding_contributions,
                         "jsonb_typeof(metadata) = 'object'",
                         name: "funding_contributions_metadata_object"

    add_column :users, :funding_badge_hidden, :boolean, null: false, default: false
    add_column :users, :funding_badge_color, :string, null: false, default: "primary"
    add_check_constraint :users,
                         "funding_badge_color IN ('primary', 'blue', 'teal', 'orange', 'purple', 'slate')",
                         name: "users_funding_badge_color"
  end
end
