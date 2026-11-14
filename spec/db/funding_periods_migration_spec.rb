# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261027100000_add_funding_subscriptions_and_paid_periods").to_s

RSpec.describe AddFundingSubscriptionsAndPaidPeriods do
  # Transactional DDL restores the current schema after each example. Exercise
  # the actual migration, not a duplicate of its backfill SQL in the spec.
  after do
    FundingContribution.reset_column_information
    FundingSubscription.reset_column_information
  end

  it "preserves all manual, revoked and unmatched facts when backfilling legacy periods" do
    paid_at = Time.utc(2024, 2, 29, 12)
    rows = [ create(:funding_contribution), create(:funding_contribution, :revoked),
      create(:funding_contribution, user: nil, provider: "stripe", external_id: "legacy_invoice",
        paid_at:, starts_at: paid_at, expires_at: paid_at + 1.year) ]
    before = rows.to_h { |row| [ row.id, row.attributes.except("starts_at", "funding_subscription_id") ] }

    migration = described_class.new
    migration.suppress_messages do
      migration.migrate(:down)
      migration.migrate(:up)
    end

    FundingContribution.reset_column_information
    rows.each do |row|
      row.reload
      expect(row.attributes.except("starts_at", "funding_subscription_id")).to eq(before.fetch(row.id))
      expect(row.starts_at).to eq(row.paid_at)
    end
  end

  it "refuses rollback while subscription identifiers could be lost" do
    create(:funding_subscription)
    migration = described_class.new
    expect { migration.suppress_messages { migration.migrate(:down) } }.to raise_error(ActiveRecord::IrreversibleMigration)
  end

  it "refuses rollback when it would discard an independent billed start" do
    create(:funding_contribution, user: nil, provider: "stripe", external_id: "historical_period",
      starts_at: 1.month.ago, expires_at: 11.months.from_now)
    migration = described_class.new
    expect { migration.suppress_messages { migration.migrate(:down) } }.to raise_error(ActiveRecord::IrreversibleMigration)
  end
end
