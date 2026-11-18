# frozen_string_literal: true

require "rails_helper"

RSpec.describe Metrics::Collector do
  before { clear_solid_queue! }

  it "fills the declared gauges from a fresh snapshot" do
    user = create(:user)
    create(:workout, user:, sport: catalog_sport("running"))

    described_class.refresh!

    expect(metric_value(:info, version: Allure::VERSION)).to eq(1)
    expect(metric_value(:users, state: "active")).to eq(User.where(suspended_at: nil).count)
    expect(metric_value(:users, state: "suspended")).to eq(0)
    expect(metric_value(:workouts)).to eq(Workout.count)
    expect(metric_value(:workouts_new_7d)).to eq(Workout.where(created_at: 7.days.ago..).count)
    expect(metric_value(:users_active_workout_7d)).to eq(1)
    expect(metric_value(:jobs_database_up)).to eq(1)
    expect(metric_value(:jobs_ready, queue: "default")).to eq(0)
    expect(metric_value(:jobs_ready, queue: "webhooks")).to eq(0)
    expect(metric_value(:jobs_ready, queue: "other")).to eq(0)
    expect(metric_value(:federation_inbox_items, status: "pending")).to eq(0)
    expect(metric_value(:federation_peer_policies)).to eq(FederationPeerPolicy.count)
    expect(metric_value(:process_threads)).to be_positive
  end

  it "counts assistant summary rows by status" do
    create(:workout_summary, :ready, workout: create(:workout))
    create(:workout_summary, :failed, workout: create(:workout))

    described_class.refresh!

    expect(metric_value(:workout_summaries, status: "ready")).to eq(1)
    expect(metric_value(:workout_summaries, status: "failed")).to eq(1)
    expect(metric_value(:workout_summaries, status: "pending")).to eq(0)
  end

  it "counts push subscriptions, never naming a device" do
    with_push_env do
      user = create(:user)
      2.times { create_push_subscription(session: user.sessions.create!(auth_method: "password")) }

      described_class.refresh!
    end

    expect(metric_value(:push_subscriptions)).to eq(2)
  end

  it "labels storage record types like the administration console" do
    workout = create(:workout, user: create(:user), sport: catalog_sport("running"))
    workout.original_file.attach(io: StringIO.new("<gpx/>"), filename: "route.gpx",
                                 content_type: "application/gpx+xml")

    described_class.refresh!

    expect(metric_value(:storage_attachments, record_type: "workout")).to be >= 1
    expect(metric_value(:storage_attachments, record_type: "Workout")).to be_nil
    expect(metric_value(:storage_bytes_by_record, record_type: "workout", name: "original_file")).to be_positive
  end

  it "marks the queue database down and emits no queue series" do
    allow(SolidQueue::ReadyExecution).to receive(:group).and_raise(ActiveRecord::ConnectionNotEstablished)

    described_class.refresh!

    expect(metric_value(:jobs_database_up)).to eq(0)
    expect(metric_value(:jobs_ready, queue: "default")).to be_nil
  end

  it "zero-fills enum series so panels do not flap" do
    described_class.refresh!

    expect(metric_value(:workout_publications, status: "active", audience: "public")).to eq(0)
    expect(metric_value(:federation_deliveries, status: "failed")).to eq(0)
    expect(metric_value(:federation_remote_actors, capability_profile: "unknown")).to eq(0)
    expect(metric_value(:segments, kind: "route", visibility: "private")).to eq(0)
    expect(metric_value(:import_batches, status: "failed", source: "exr")).to eq(0)
    expect(metric_value(:import_connections, provider: "exr", status: "revoked")).to eq(0)
    expect(metric_value(:import_connection_errors, provider: "garmin_connect")).to eq(0)
  end

  it "reports remote import connections by provider and state, and the stalest sync" do
    with_remote_import_enabled do
      create(:import_connection, :linked, last_synced_at: 3.hours.ago, last_sync_error: "down")
      create(:import_connection, :linked, last_synced_at: 10.minutes.ago)
      create(:import_connection, provider: "exr", status: "expired")
      create(:workout_import_batch, user: create(:user), sport: nil, source: "garmin_connect",
                                    import_connection: ImportConnection.first)
      Metrics::Cache.reset!

      described_class.refresh!

      expect(metric_value(:import_connections, provider: "garmin_connect", status: "linked")).to eq(2)
      expect(metric_value(:import_connections, provider: "exr", status: "expired")).to eq(1)
      expect(metric_value(:import_connection_errors, provider: "garmin_connect")).to eq(1)
      expect(metric_value(:import_connection_sync_age_seconds, provider: "garmin_connect")).to be_within(60).of(3.hours)
      expect(metric_value(:import_connection_sync_age_seconds, provider: "exr")).to eq(0)
      expect(metric_value(:import_batches, status: "queued", source: "garmin_connect")).to eq(1)
    end
  end
end
