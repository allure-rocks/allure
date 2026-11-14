# frozen_string_literal: true

# PLAN_FUNDING.md §3 (PAY-105): verified reversal signals (refunds and
# disputes) are recorded in their own rows, separately from the immutable
# original payments, so the operator can review them in /admin/funding.
# The reversal's lifecycle (open → won/lost, succeeded → failed) updates
# its own row; the contribution it refers to is never rewritten.
class CreateFundingReversals < ActiveRecord::Migration[8.1]
  def change
    create_table :funding_reversals do |t|
      t.references :funding_contribution, null: false, foreign_key: { on_delete: :cascade }
      t.string :provider, null: false
      t.string :external_id, null: false
      t.string :kind, null: false
      t.string :status, null: false
      t.bigint :amount_cents
      t.string :currency, limit: 3
      t.datetime :reported_at, null: false
      t.timestamps

      t.index %i[provider external_id], unique: true
    end

    add_check_constraint :funding_reversals,
                         "provider ~ '\\A[a-z0-9_]+\\Z'",
                         name: "funding_reversals_provider_format"
    add_check_constraint :funding_reversals,
                         "length(btrim(external_id)) > 0",
                         name: "funding_reversals_external_id_present"
    add_check_constraint :funding_reversals,
                         "kind IN ('refund', 'dispute')",
                         name: "funding_reversals_kind"
    add_check_constraint :funding_reversals,
                         "status IN ('succeeded', 'failed', 'open', 'won', 'lost')",
                         name: "funding_reversals_status"
    add_check_constraint :funding_reversals,
                         "amount_cents IS NULL OR amount_cents >= 0",
                         name: "funding_reversals_amount_nonnegative"
    add_check_constraint :funding_reversals,
                         "currency IS NULL OR currency ~ '\\A[A-Z]{3}\\Z'",
                         name: "funding_reversals_currency_format"
  end
end
