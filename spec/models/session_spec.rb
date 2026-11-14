# frozen_string_literal: true

require "rails_helper"

RSpec.describe Session do
  let(:user) { create(:user) }
  let(:now) { Time.zone.parse("2026-10-09 12:00") }

  def session_at(created_at:, last_seen_at: created_at, reauthenticated_at: nil)
    user.sessions.create!(created_at:, last_seen_at:, reauthenticated_at:)
  end

  describe "#expired?" do
    it "stays live inside both lifetimes" do
      expect(session_at(created_at: now - 89.days, last_seen_at: now - 29.days)).not_to be_expired(now)
    end

    it "expires after the idle timeout" do
      expect(session_at(created_at: now - 40.days, last_seen_at: now - 30.days)).to be_expired(now)
    end

    it "expires at the absolute lifetime even while active" do
      expect(session_at(created_at: now - 90.days, last_seen_at: now - 1.minute)).to be_expired(now)
    end
  end

  it "partitions rows into live and expired scopes" do
    live = session_at(created_at: now - 1.day)
    idle = session_at(created_at: now - 40.days, last_seen_at: now - 31.days)
    old = session_at(created_at: now - 91.days, last_seen_at: now)

    expect(described_class.live(now)).to contain_exactly(live)
    expect(described_class.expired(now)).to contain_exactly(idle, old)
  end

  it "caps the cookie at the absolute lifetime" do
    expect(session_at(created_at: now).expires_at).to eq(now + 90.days)
  end

  describe "#record_activity!" do
    it "writes at most once per refresh interval" do
      session = session_at(created_at: now - 1.hour, last_seen_at: now - 4.minutes)

      expect { session.record_activity!(now) }.not_to(change { session.reload.last_seen_at })

      session.update_column(:last_seen_at, now - 6.minutes)
      session.record_activity!(now)

      expect(session.reload.last_seen_at).to be_within(1.second).of(now)
    end
  end

  describe "#recently_authenticated?" do
    it "holds for ten minutes after a proof of identity" do
      session = session_at(created_at: now - 1.hour)
      expect(session).not_to be_recently_authenticated(now)

      session.reauthenticate!(now - 9.minutes)
      expect(session).to be_recently_authenticated(now)
      expect(session).not_to be_recently_authenticated(now + 2.minutes)
    end
  end
end
