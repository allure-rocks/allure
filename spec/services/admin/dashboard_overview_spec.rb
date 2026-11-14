# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Dashboard::Overview do
  let(:user) { create(:user) }

  it "aggregates instance counts and the most recent rows" do
    create(:workout, user:, sport: catalog_sport("running"))

    result = described_class.new.call

    expect(result.accounts[:total]).to eq(User.count)
    expect(result.accounts[:active_week]).to eq(Users::Engagement.new.active(since: 7.days.ago))
    expect(result.accounts[:connected]).to eq(Session.distinct.count(:user_id))
    expect(result.workouts[:total]).to eq(Workout.count)
    expect(result.workouts[:distance].to_i).to eq(Workout.sum(:distance).to_i)
    expect(result.workouts[:moving_time]).to eq(Workout.sum(:moving_time))
    expect(result.recent_accounts).to include(user)
    expect(result.publications).to include(:active, :public, :followers, :courses)
    expect(result.federation).to include(:remote_actors, :followed, :pending_follows)
    expect(result.storage[:blobs]).to eq(ActiveStorage::Blob.count)
  end

  it "keeps the dashboard usable when the queue database is unreachable" do
    allow(SolidQueue::ReadyExecution).to receive(:count).and_raise(ActiveRecord::ConnectionNotEstablished)

    expect(described_class.new.call.queue).to be_nil
  end
end
