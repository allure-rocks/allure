# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261031090000_add_profile_sharing_audiences_to_users").to_s

RSpec.describe AddProfileSharingAudiencesToUsers do
  # Transactional DDL restores the current schema after each example, as with
  # the other migration specs. Exercise the real SQL and reset the model cache.
  after { User.reset_column_information }

  it "preserves the four combinations of existing sharing choices independently" do
    rows = %w[none members].product(%w[none members]).map do |statistics, records|
      create(:user, profile_statistics_audience: statistics, profile_records_audience: records)
    end
    expected = rows.to_h { |user| [ user.id, [ user.profile_statistics_audience, user.profile_records_audience ] ] }
    migration = described_class.new

    migration.suppress_messages do
      migration.migrate(:down)
      legacy = ActiveRecord::Base.connection.select_all("SELECT id, share_profile_statistics, share_profile_records FROM users")
      rows.each do |user|
        row = legacy.find { |candidate| candidate["id"] == user.id }
        expect([ row["share_profile_statistics"], row["share_profile_records"] ]).to eq(expected.fetch(user.id).map { |audience| audience == "members" })
      end
      migration.migrate(:up)
    end

    User.reset_column_information
    rows.each do |user|
      expect(user.reload.attributes.values_at("profile_statistics_audience", "profile_records_audience")).to eq(expected.fetch(user.id))
    end
    expect(User.column_names).not_to include("share_profile_statistics", "share_profile_records")
  end

  it "refuses rollback rather than widening a followers-only audience" do
    create(:user, profile_records_audience: "followers")
    migration = described_class.new

    expect { migration.suppress_messages { migration.migrate(:down) } }.to raise_error(ActiveRecord::IrreversibleMigration)
  end
end
