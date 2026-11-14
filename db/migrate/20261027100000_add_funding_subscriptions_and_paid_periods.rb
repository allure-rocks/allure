# frozen_string_literal: true

class AddFundingSubscriptionsAndPaidPeriods < ActiveRecord::Migration[8.1]
  def up
    create_table :funding_subscriptions do |t|
      t.references :user, null: true, foreign_key: { on_delete: :cascade }
      t.string :provider, null: false
      t.string :external_id, null: false
      t.string :customer_id, null: false
      t.string :tier, null: false
      t.string :status, null: false, default: "incomplete"
      t.boolean :cancel_at_period_end, null: false, default: false
      t.datetime :canceled_at
      t.datetime :synced_at
      t.timestamps

      t.index %i[provider external_id], unique: true
    end

    add_check_constraint :funding_subscriptions,
      "provider ~ '^[a-z0-9_]+$' AND provider <> 'manual'", name: "funding_subscriptions_provider"
    add_check_constraint :funding_subscriptions,
      "length(btrim(external_id)) > 0 AND length(btrim(customer_id)) > 0", name: "funding_subscriptions_identifiers"
    add_check_constraint :funding_subscriptions,
      "tier IN ('coffee', 'beer', 'energy')", name: "funding_subscriptions_tier"
    add_check_constraint :funding_subscriptions,
      "status IN ('incomplete', 'active', 'past_due', 'paused', 'canceled')", name: "funding_subscriptions_status"

    add_reference :funding_contributions, :funding_subscription, null: true, foreign_key: true
    add_column :funding_contributions, :starts_at, :datetime
    # Preserve every existing expiry, including revoked and unmatched rows.
    execute "UPDATE funding_contributions SET starts_at = paid_at"
    change_column_null :funding_contributions, :starts_at, false
    remove_check_constraint :funding_contributions, name: "funding_contributions_period"
    add_check_constraint :funding_contributions, "expires_at > starts_at", name: "funding_contributions_period"
    add_check_constraint :funding_contributions,
      "provider <> 'manual' OR funding_subscription_id IS NULL", name: "funding_contributions_manual_subscription"
  end

  def down
    # Refuse to silently convert a billed period to a year from payment. Late
    # payments may even post after period end, which the old check disallows.
    if select_value("SELECT EXISTS (SELECT 1 FROM funding_subscriptions) OR EXISTS (SELECT 1 FROM funding_contributions WHERE expires_at <= paid_at OR starts_at <> paid_at)")
      raise ActiveRecord::IrreversibleMigration, "Subscription contributions require explicit reconciliation before rollback"
    end

    remove_check_constraint :funding_contributions, name: "funding_contributions_manual_subscription"
    remove_check_constraint :funding_contributions, name: "funding_contributions_period"
    add_check_constraint :funding_contributions, "expires_at > paid_at", name: "funding_contributions_period"
    remove_column :funding_contributions, :starts_at
    remove_reference :funding_contributions, :funding_subscription, foreign_key: true
    drop_table :funding_subscriptions
  end
end
