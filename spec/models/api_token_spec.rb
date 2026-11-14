# frozen_string_literal: true

require "rails_helper"

RSpec.describe ApiToken do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create(:user) }

  describe ".issue!" do
    it "returns a prefixed secret and keeps only its digest" do
      token, secret = described_class.issue!(user:, name: " Dashboard ", scopes: %w[read read webhooks bogus])

      expect(secret).to match(described_class::SECRET_PATTERN)
      expect(token.token_digest).to eq(OpenSSL::Digest::SHA256.hexdigest(secret))
      expect(token.token_prefix).to eq(secret.first(12))
      expect(token.attributes.values.map(&:to_s)).not_to include(secret)
      expect(token.name).to eq("Dashboard")
      expect(token.scopes).to eq(%w[read webhooks])
    end

    it "bounds the expiry to the offered choices" do
      freeze_time do
        token, = described_class.issue!(user:, name: "A", scopes: %w[read], expires_in_days: 365)
        other, = described_class.issue!(user:, name: "B", scopes: %w[read], expires_in_days: 9_999)

        expect(token.expires_at).to eq(365.days.from_now)
        expect(other.expires_at).to eq(90.days.from_now)
      end
    end

    it "refuses a token without a scope" do
      expect { described_class.issue!(user:, name: "Empty", scopes: []) }
        .to raise_error(ActiveRecord::RecordInvalid)
    end

    it "caps the usable tokens per account" do
      described_class::MAX_LIVE_PER_USER.times { |index| described_class.issue!(user:, name: "T#{index}", scopes: %w[read]) }

      expect { described_class.issue!(user:, name: "One more", scopes: %w[read]) }
        .to raise_error(ActiveRecord::RecordInvalid, /20/)
    end
  end

  describe ".authenticate" do
    it "finds a usable token from its secret" do
      token, secret = described_class.issue!(user:, name: "A", scopes: %w[read])

      expect(described_class.authenticate(secret)).to eq(token)
    end

    it "refuses malformed, unknown, revoked and expired secrets" do
      revoked, revoked_secret = described_class.issue!(user:, name: "R", scopes: %w[read])
      revoked.revoke!(by: "owner")
      expired, expired_secret = described_class.issue!(user:, name: "E", scopes: %w[read])
      expired.update_columns(expires_at: 1.minute.ago)

      expect(described_class.authenticate(nil)).to be_nil
      expect(described_class.authenticate("allure_pat_short")).to be_nil
      expect(described_class.authenticate("allure_pat_#{'a' * 43}")).to be_nil
      expect(described_class.authenticate(revoked_secret)).to be_nil
      expect(described_class.authenticate(expired_secret)).to be_nil
    end
  end

  describe "#record_use!" do
    it "refreshes the last use at most every five minutes" do
      token, = described_class.issue!(user:, name: "A", scopes: %w[read])
      first = Time.zone.parse("2026-10-11 10:00:00")

      token.record_use!(first)
      token.record_use!(first + 4.minutes)
      expect(token.reload.last_used_at).to eq(first)

      token.record_use!(first + 6.minutes)
      expect(token.reload.last_used_at).to eq(first + 6.minutes)
    end
  end

  describe ".prunable" do
    it "selects tokens revoked or expired more than 90 days ago" do
      old, = described_class.issue!(user:, name: "Old", scopes: %w[read])
      old.update_columns(revoked_at: 91.days.ago, revoked_by: "owner")
      recent, = described_class.issue!(user:, name: "Recent", scopes: %w[read])
      recent.update_columns(revoked_at: 1.day.ago, revoked_by: "owner")
      live, = described_class.issue!(user:, name: "Live", scopes: %w[read])

      expect(described_class.prunable).to contain_exactly(old)
      ApiTokens::PruneJob.perform_now
      expect(described_class.where(id: [ old.id, recent.id, live.id ]).pluck(:id)).to contain_exactly(recent.id, live.id)
    end
  end

  it "enforces the scope vocabulary in the database" do
    token, = described_class.issue!(user:, name: "A", scopes: %w[read])

    expect { token.update_columns(scopes: %w[admin]) }.to raise_error(ActiveRecord::StatementInvalid)
  end

  describe "MCP location level (PLAN_MCP.md §4)" do
    def with_ceiling(value)
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("MCP_GEOMETRY_MAX", "").and_return(value)
    end

    it "defaults to none and is constrained in the database" do
      token, = described_class.issue!(user:, name: "A", scopes: %w[read])

      expect(token.mcp_geometry).to eq("none")
      expect { token.update_columns(mcp_geometry: "everything") }.to raise_error(ActiveRecord::StatementInvalid)
    end

    it "offers every level without a ceiling, and lowers a token to the ceiling" do
      token, = described_class.issue!(user:, name: "A", scopes: %w[read], mcp_geometry: "raw")
      expect(described_class.offered_mcp_geometry_levels).to eq(%w[none filtered raw])
      expect(token.effective_mcp_geometry).to eq("raw")

      with_ceiling("filtered")
      expect(described_class.offered_mcp_geometry_levels).to eq(%w[none filtered])
      expect(token.effective_mcp_geometry).to eq("filtered")

      with_ceiling("none")
      expect(token.effective_mcp_geometry).to eq("none")
    end

    it "ignores an unknown ceiling and refuses a new token above a known one" do
      with_ceiling("bogus")
      expect(described_class.mcp_geometry_cap).to eq("raw")

      with_ceiling("none")
      expect { described_class.issue!(user:, name: "A", scopes: %w[read], mcp_geometry: "filtered") }
        .to raise_error(ActiveRecord::RecordInvalid)
    end
  end
end
