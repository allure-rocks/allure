# frozen_string_literal: true

require "rails_helper"

RSpec.describe Users::PruneExpiredSessionsJob do
  it "deletes expired sessions and keeps live ones" do
    user = create(:user)
    live = user.sessions.create!
    idle = user.sessions.create!(created_at: 40.days.ago, last_seen_at: 31.days.ago)
    old = user.sessions.create!(created_at: 91.days.ago, last_seen_at: 1.minute.ago)

    described_class.perform_now

    expect(Session.where(id: [ live, idle, old ].map(&:id))).to contain_exactly(live)
  end
end
