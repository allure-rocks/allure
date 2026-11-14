# frozen_string_literal: true

require "rails_helper"

RSpec.describe Metrics::Snapshot do
  let(:user) { create(:user) }

  it "distinguishes upcoming paid periods from current badges, with revocation taking precedence", :funding do
    create(:funding_contribution, :subscription, starts_at: 1.day.from_now)
    create(:funding_contribution, :subscription, :revoked, starts_at: 1.day.from_now)
    create(:funding_contribution, :subscription, :expired)
    create(:funding_contribution, :subscription)

    counts = described_class.new.call.domain.fetch(:funding_contributions)
    %w[active upcoming expired revoked].each do |status|
      expect(counts.fetch([ "stripe", "beer", status ])).to eq(1)
    end
  end

  it "aggregates account, workout, and publication counts" do
    create(:workout, user:, sport: catalog_sport("running"))
    create(:user, suspended_at: Time.current)

    snapshot = described_class.new.call

    expect(snapshot.domain[:users]).to eq(active: User.where(suspended_at: nil).count,
                                          suspended: User.where.not(suspended_at: nil).count)
    expect(snapshot.domain[:workouts]).to eq(Workout.count)
    expect(snapshot.domain[:workouts_distance_meters]).to eq(Workout.sum(:distance).to_f)
    expect(snapshot.domain[:workouts_moving_seconds]).to eq(Workout.sum(:moving_time))
    expect(snapshot.domain[:workouts_new_7d]).to eq(Workout.where(created_at: 7.days.ago..).count)
    expect(snapshot.domain[:segment_efforts]).to eq(SegmentEffort.count)
  end

  it "counts active users from workout and publication activity" do
    create(:workout, user:, sport: catalog_sport("running"))

    snapshot = described_class.new.call

    expect(snapshot.activity["workout_7d"]).to eq(Workout.where(created_at: 7.days.ago..).distinct.count(:user_id))
    expect(snapshot.activity["workout_30d"]).to be >= snapshot.activity["workout_7d"]
    expect(snapshot.activity["active_7d"]).to be >= snapshot.activity["workout_7d"]
    expect(snapshot.activity["publication_7d"]).to eq(0)
  end

  it "counts connected users from open sessions" do
    user.sessions.create!(user_agent: "browser", ip_address: "127.0.0.1")

    snapshot = described_class.new.call

    expect(snapshot.users[:sessions_open]).to eq(Session.count)
    expect(snapshot.users[:users_connected]).to eq(Session.distinct.count(:user_id))
  end

  it "counts federation statuses without identifiers" do
    create(:remote_note, status: "active")

    snapshot = described_class.new.call

    expect(snapshot.federation[:remote_notes].fetch("active")).to be >= 1
    expect(snapshot.federation[:inbox_items]).to be_a(Hash)
    expect(snapshot.federation[:remote_actors]).to be_a(Hash)
    expect(snapshot.federation[:blocked_domains]).to eq(FederationDomainBlock.count)
  end

  it "omits the jobs family when the queue database is unreachable" do
    allow(SolidQueue::ReadyExecution).to receive(:group).and_raise(ActiveRecord::ConnectionNotEstablished)

    expect(described_class.new.call.jobs).to be_nil
  end

  it "reports queue counts, processes, and recurring tasks when reachable" do
    clear_solid_queue!
    create_ready_job(queue_name: "default")
    create_failed_job(queue_name: "route_images")

    snapshot = described_class.new.call

    expect(snapshot.jobs[:queues]["default"][:ready]).to eq(1)
    expect(snapshot.jobs[:queues]["route_images"][:failed]).to eq(1)
    expect(snapshot.jobs[:processes]).to include(:alive, :stale)
  end

  it "reports the webhooks queue under its own name" do
    clear_solid_queue!
    create_ready_job(queue_name: "webhooks")

    queues = described_class.new.call.jobs[:queues]

    expect(queues["webhooks"][:ready]).to eq(1)
    expect(queues).not_to have_key("other")
  end
end
