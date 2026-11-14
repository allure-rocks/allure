# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workouts::WorkoutDeletion do
  let(:user) { create(:user) }
  let(:workout) { create(:workout, user:) }
  let!(:track_segment) { create(:track_segment, workout:) }
  let(:profile) { create(:publishing_profile, :without_endpoint_masks, user:) }

  before { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }
  after { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }

  it "deletes an unpublished workout normally" do
    expect { described_class.new(user:, workout:).call! }.to change(Workout, :count).by(-1)
  end

  it "withdraws then destroys, retaining deleted identity without its source" do
    publication = publish_workout!(user:, workout:, profile:)
    create_event = FederationOutboxEvent.find_by!(activity_type: "Create", object_uri: publication.object_uri)
    delivery = create(
      :federation_delivery,
      outbox_event: create_event,
      status: "delivered",
      inbox_url: "https://remote.example/inbox-#{SecureRandom.hex(4)}"
    )
    create(:federation_delivery_recipient, delivery:, actor_uri: "https://remote.example/users/follower")
    publication_id = publication.id
    object_uri = publication.object_uri

    result = described_class.new(user:, workout:).call!

    expect(Workout.find_by(id: workout.id)).to be_nil
    retained = WorkoutPublication.find(publication_id)
    expect(retained).to be_deleted
    expect(retained.workout_id).to be_nil
    expect(retained.actor).to be_present
    expect(retained.object_uri).to eq(object_uri)
    delete_event = FederationOutboxEvent.find_by!(activity_type: "Delete", object_uri:)
    expect(delete_event.audience["recipients"]).to contain_exactly("https://remote.example/users/follower")
    expect(result.delete_events.map(&:id)).to eq([ delete_event.id ])
  end

  it "preserves the source when withdrawal persistence fails" do
    publish_workout!(user:, workout:, profile:)
    allow(Workouts::PublicationWithdrawal).to receive(:new).and_raise(StandardError, "withdrawal unavailable")

    expect { described_class.new(user:, workout:).call! }.to raise_error(StandardError, "withdrawal unavailable")
    expect(Workout.find_by(id: workout.id)).to be_present
    expect(workout.reload.active_publications.first).to be_active
  end

  it "prevents direct destruction of a published source at the database boundary" do
    publish_workout!(user:, workout:, profile:)

    expect { workout.destroy! }.to raise_error(ActiveRecord::StatementInvalid)
  end

  it "rolls back withdrawal when source destruction fails" do
    publication = publish_workout!(user:, workout:, profile:)
    allow(workout).to receive(:destroy!).and_raise(ActiveRecord::RecordNotDestroyed, "source locked")

    expect { described_class.new(user:, workout:).call! }.to raise_error(ActiveRecord::RecordNotDestroyed)
    expect(publication.reload).to be_active
    expect(FederationOutboxEvent.where(activity_type: "Delete", object_uri: publication.object_uri).count).to eq(0)
    expect(Workout.find_by(id: workout.id)).to be_present
  end

  it "cancels a scheduled publication with no federation trace" do
    publication = Workouts::Publisher.new(
      user:, workout:, profile:, delay: PublishingProfile::PUBLISH_DELAYS.fetch("1_day")
    ).call!
    publication_id = publication.id

    result = described_class.new(user:, workout:).call!

    expect(Workout.find_by(id: workout.id)).to be_nil
    expect(WorkoutPublication.find(publication_id)).to be_deleted
    expect(FederationOutboxEvent.where(workout_publication_id: publication_id)).to be_empty
    expect(result.publications).to be_empty
    expect(result.delete_events).to be_empty
  end

  it "rolls back a scheduled cancellation when source destruction fails" do
    publication = Workouts::Publisher.new(
      user:, workout:, profile:, delay: PublishingProfile::PUBLISH_DELAYS.fetch("1_day")
    ).call!
    allow(workout).to receive(:destroy!).and_raise(ActiveRecord::RecordNotDestroyed, "source locked")

    expect { described_class.new(user:, workout:).call! }.to raise_error(ActiveRecord::RecordNotDestroyed)
    expect(publication.reload).to be_scheduled
    expect(Workout.find_by(id: workout.id)).to be_present
  end
end
