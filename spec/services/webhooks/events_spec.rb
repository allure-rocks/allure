# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Webhook events at their call sites (PLAN_API.md §11.2)" do
  let(:user) { create(:user) }
  let!(:endpoint) { user.webhook_endpoints.create!(url: "https://hooks.example.com/", events: [ "*" ]) }
  let(:workout) { create(:workout, user:) }

  def events(type) = WebhookEvent.where(user:, event_type: type)

  it "announces an imported workout, without geometry or free text" do
    upload = Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/gpx/galibier.gpx"), "application/gpx+xml")

    result = Workouts::Importer.new(user:, uploaded_file: upload, sport: catalog_sport("cycling")).call

    payload = events("workout.created").sole.payload
    expect(payload.dig("workout", "id")).to eq(result.workout.to_param)
    expect(payload["workout"]).not_to include("notes", "description", "track")
    expect(payload.to_s).not_to match(/coordinates|"lat"|"lon"/)
  end

  it "announces the analysis once per analysis version, when every enrichment settled" do
    allow(Workouts::AutoPublicationReadiness).to receive(:new).and_return(instance_double(Workouts::AutoPublicationReadiness, ready?: false))
    Workouts::AutoPublishJob.nudge(workout)
    expect(events("workout.analyzed")).to be_empty

    allow(Workouts::AutoPublicationReadiness).to receive(:new).and_return(instance_double(Workouts::AutoPublicationReadiness, ready?: true))
    2.times { Workouts::AutoPublishJob.nudge(workout) }
    expect(events("workout.analyzed").count).to eq(1)

    workout.update_columns(analysis_version: workout.analysis_version + 1)
    Workouts::AutoPublishJob.nudge(workout)
    expect(events("workout.analyzed").count).to eq(2)
  end

  it "announces an owner's bulk commute change for each workout it changed" do
    other = create(:workout, user:, commute: true)

    Workouts::BulkQuickAction.new(user:, workout_ids: [ workout.id, other.id ], action: "commute_on").call!

    expect(events("workout.updated").map { [ it.payload.dig("workout", "id"), it.payload["changed"] ] })
      .to eq([ [ workout.to_param, [ "commute" ] ] ])
  end

  it "announces a deletion, and the withdrawal of its live publication" do
    create(:track_segment, workout:)
    profile = create(:publishing_profile, :without_endpoint_masks, user:)
    publication = Workouts::Publisher.new(user:, workout:, profile:).call!
    expect(events("publication.activated").sole.payload.dig("publication", "id")).to eq(publication.to_param)

    Workouts::WorkoutDeletion.new(user:, workout:).call!

    expect(events("workout.deleted").sole.payload).to eq("workout_id" => workout.to_param)
    expect(events("publication.withdrawn").sole.payload).to include("publication_id" => publication.to_param,
                                                                     "reason" => "workout_deleted")
  end

  it "names a replacement and a cancellation as such" do
    create(:track_segment, workout:)
    profile = create(:publishing_profile, :without_endpoint_masks, user:)
    first = Workouts::Publisher.new(user:, workout:, profile:).call!
    Workouts::PublicationReplacement.new(user:, workout:, profile:, publication: first).call!
    scheduled = Workouts::Publisher.new(user:, workout: create(:workout, user:).tap { create(:track_segment, workout: it) },
                                        profile:, delay: PublishingProfile::PUBLISH_DELAYS.fetch("1_day")).call!
    Workouts::ScheduledPublicationCancellation.new(user:, publication: scheduled).call!

    expect(events("publication.withdrawn").map { it.payload["reason"] }).to contain_exactly("replaced", "cancelled")
    expect(events("publication.activated").count).to eq(2)
  end

  it "emits nothing to an account without webhooks" do
    endpoint.destroy!

    Workouts::BulkQuickAction.new(user:, workout_ids: [ workout.id ], action: "commute_on").call!
    Workouts::WorkoutDeletion.new(user:, workout:).call!

    expect(WebhookEvent.count).to eq(0)
  end

  it "never lets a webhook failure break the fact it announces" do
    allow(Webhooks::Emit).to receive(:call).and_raise("boom")

    expect { Workouts::WorkoutDeletion.new(user:, workout:).call! }.not_to raise_error
    expect(Workout.exists?(workout.id)).to be(false)
  end
end
