# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workouts::ScheduledPublicationActivation do
  let(:user) { create(:user) }
  let(:workout) { create(:workout, user:) }

  def scheduled_publication(scheduled_for: 1.hour.ago, profile: nil)
    profile ||= create(:publishing_profile,
                       settings: PublishingProfile::DEFAULT_SETTINGS.merge("route_image" => false),
                       user:)
    create(:workout_publication, :scheduled,
           workout:, publishing_profile: profile, scheduled_for:)
  end

  it "activates a due publication and creates its pending Create intent" do
    publication = scheduled_publication
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    result = described_class.new(publication:).call!

    expect(result).to be_a(described_class::Result)
    expect(publication.reload).to be_active
    event = result.outbox_event
    expect(event).to be_pending
    expect(event.activity_type).to eq("Create")
    expect(event.workout_publication_id).to eq(publication.id)
    expect(workout.reload.active_publications.first).to eq(publication)
    expect(Federation::ExpandOutboxEventJob).to have_been_enqueued
  end

  it "keeps the intent preparing while the route image is still expected" do
    profile = create(:publishing_profile, user:)
    publication = scheduled_publication(profile:)
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    result = described_class.new(publication:).call!

    expect(result.outbox_event).to be_preparing
    expect(Workouts::RenderPublicationRouteImageJob).to have_been_enqueued
    expect(Federation::ExpandOutboxEventJob).not_to have_been_enqueued
  end

  it "defers when the job fires before the planned moment" do
    publication = scheduled_publication(scheduled_for: 2.hours.from_now)
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    expect(described_class.new(publication:).call!).to eq(:deferred)
    expect(publication.reload).to be_scheduled
    expect(Workouts::ActivateScheduledPublicationJob).to have_been_enqueued.at(publication.scheduled_for)
    expect(FederationOutboxEvent.where(workout_publication_id: publication.id)).to be_empty
  end

  it "activates early when forced by the owner" do
    publication = scheduled_publication(scheduled_for: 1.month.from_now)

    result = described_class.new(publication:, force: true).call!

    expect(publication.reload).to be_active
    expect(publication.published_at).to be_within(2.seconds).of(Time.current)
    expect(result.outbox_event).to be_pending
  end

  it "is idempotent" do
    publication = scheduled_publication

    described_class.new(publication:).call!
    second = described_class.new(publication:).call!

    expect(second).to be_nil
    expect(FederationOutboxEvent.where(workout_publication_id: publication.id, activity_type: "Create").count).to eq(1)
  end

  it "rolls the activation back when the outbox intent cannot be persisted" do
    publication = scheduled_publication
    allow(Federation::Outbox::EventBuilder).to receive(:new).and_raise(StandardError, "outbox unavailable")

    expect { described_class.new(publication:).call! }
      .to raise_error(StandardError, "outbox unavailable")
    expect(publication.reload).to be_scheduled
    expect(FederationOutboxEvent.where(workout_publication_id: publication.id)).to be_empty
  end

  it "notifies the owner once when the publication goes live" do
    publication = scheduled_publication

    expect { described_class.new(publication:).call! }.to change(Notification, :count).by(1)

    notification = user.notifications.last
    expect(notification.kind).to eq("publication_activated")
    expect(notification.actor).to be_nil
    expect(notification.subject).to eq(publication)
    expect(notification.payload).to eq("audience" => "public")

    expect { described_class.new(publication:).call! }.not_to change(Notification, :count)
  end

  it "does not notify on the owner-triggered immediate path" do
    publication = scheduled_publication

    expect { described_class.activate_now(publication) }.not_to change(Notification, :count)
    expect(publication.reload).to be_active
  end

  it "honors the activation notification preference" do
    publication = scheduled_publication
    user.update!(notify_publication_activated: false)

    expect { described_class.new(publication:).call! }.not_to change(Notification, :count)
  end

  it "sweeps only due publications" do
    profile = create(:publishing_profile,
                     settings: PublishingProfile::DEFAULT_SETTINGS.merge("route_image" => false),
                     user:)
    due = scheduled_publication(scheduled_for: 1.minute.ago, profile:)
    future_workout = create(:workout, user:)
    future = create(:workout_publication, :scheduled,
                    workout: future_workout, publishing_profile: profile,
                    scheduled_for: 1.hour.from_now)

    activated = described_class.sweep

    expect(activated).to eq(1)
    expect(due.reload).to be_active
    expect(future.reload).to be_scheduled
  end

  describe "the owner's deletion window (docs/dev/ACCOUNT.md)" do
    def schedule_deletion
      user.update!(deletion_requested_at: Time.current, deletion_scheduled_at: 1.day.from_now,
                   deletion_requested_by: "self")
    end

    it "leaves a due publication scheduled while the window is open" do
      publication = scheduled_publication
      schedule_deletion

      expect(described_class.new(publication:).call!).to be_nil
      expect(publication.reload).to be_scheduled
      expect(FederationOutboxEvent.where(workout_publication_id: publication.id)).to be_empty
      expect(Notification.where(kind: "publication_activated")).to be_empty
    end

    it "skips it in the sweep and activates it once the window is cancelled" do
      publication = scheduled_publication
      schedule_deletion

      expect(described_class.sweep).to eq(0)
      expect(publication.reload).to be_scheduled

      user.update!(deletion_requested_at: nil, deletion_scheduled_at: nil, deletion_requested_by: nil)

      expect(described_class.sweep).to eq(1)
      expect(publication.reload).to be_active
    end

    it "refuses a forced activation too" do
      publication = scheduled_publication(scheduled_for: 1.month.from_now)
      schedule_deletion

      expect(described_class.new(publication:, force: true).call!).to be_nil
      expect(publication.reload).to be_scheduled
    end
  end
end
