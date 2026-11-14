# frozen_string_literal: true

require "rails_helper"

RSpec.describe Users::Engagement do
  let(:running) { catalog_sport("running") }

  it "counts distinct users with workouts in the window" do
    create(:workout, user: create(:user), sport: running)
    create(:workout, user: create(:user), sport: running)

    expect(described_class.new.active_workout(since: 7.days.ago))
      .to eq(Workout.where(created_at: 7.days.ago..).distinct.count(:user_id))
  end

  it "counts distinct publishers of active publications" do
    create(:workout_publication, workout: create(:workout, user: create(:user), sport: running))

    expect(described_class.new.active_publication(since: 7.days.ago)).to eq(1)
  end

  it "unions workout and publication activity without double counting" do
    user = create(:user)
    create(:workout_publication, workout: create(:workout, user:, sport: running))
    create(:workout, user: create(:user), sport: running)

    expect(described_class.new.active(since: 7.days.ago)).to eq(2)
  end

  it "counts open sessions and connected users" do
    user = create(:user)
    user.sessions.create!(user_agent: "browser", ip_address: "127.0.0.1")

    engagement = described_class.new

    expect(engagement.open_sessions).to eq(Session.count)
    expect(engagement.connected).to eq(Session.distinct.count(:user_id))
  end
end
