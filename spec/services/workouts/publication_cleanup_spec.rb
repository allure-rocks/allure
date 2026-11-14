# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workouts::PublicationCleanup do
  let(:owner) { create(:user) }
  let(:workout) { create(:workout, user: owner) }
  let!(:track_segment) { create(:track_segment, workout:) }
  let(:profile) { create(:publishing_profile, :without_endpoint_masks, user: owner) }

  before { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }
  after { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }

  def publish_and_withdraw!
    publication = publish_workout!(user: owner, workout:, profile:)
    withdrawal = Workouts::PublicationWithdrawal.new(user: owner, workout:).call!
    [ publication, withdrawal.delete_event ]
  end

  def complete_event!(event)
    Federation::Outbox::Expander.new(event:).call!
    event.reload
  end

  def settle_publication!(publication)
    FederationOutboxEvent.where(workout_publication_id: publication.id).find_each do |event|
      complete_event!(event)
    end
  end

  describe "eligibility" do
    it "never cleans an active publication" do
      publication = publish_workout!(user: owner, workout:, profile:)

      expect { described_class.new(publication:).call! }.to raise_error(described_class::NotEligible)
      expect(publication.reload.location_data_purged_at).to be_nil
    end

    it "blocks cleanup while a Create is still pending" do
      publication, _delete_event = publish_and_withdraw!

      expect { described_class.new(publication:).call! }.to raise_error(described_class::NotEligible)
    end

    it "blocks cleanup while deliveries are retrying or reconciling" do
      publication, _delete_event = publish_and_withdraw!
      create_event = FederationOutboxEvent.find_by!(activity_type: "Create", object_uri: publication.object_uri)
      create_event.update!(status: "expanded")
      create(
        :federation_delivery,
        outbox_event: create_event,
        status: "retrying",
        next_attempt_at: 1.hour.from_now,
        inbox_url: "https://remote.example/inbox-retry"
      )

      expect { described_class.new(publication:).call! }.to raise_error(described_class::NotEligible)

      FederationDelivery.where(outbox_event: create_event).update_all(status: "reconciling")

      expect { described_class.new(publication:).call! }.to raise_error(described_class::NotEligible)
    end
  end

  describe "terminal cleanup" do
    let!(:publication) do
      publication, _delete_event = publish_and_withdraw!
      settle_publication!(publication)
      publication.reload
    end
    let(:create_event) do
      FederationOutboxEvent.find_by!(activity_type: "Create", object_uri: publication.object_uri)
    end
    let(:original_payload) { create_event.payload.deep_dup }

    it "purges media, redacts coordinates, and keeps the audit subset" do
      expect(publication.representation["track"]).to be_present

      result = described_class.new(publication:).call!

      expect(result.cleaned).to be(true)
      cleaned = result.publication
      expect(cleaned.location_data_purged_at).to be_present
      expect(cleaned.representation.keys).to contain_exactly(
        "title", "description", "metrics", "sport_slug", "started_at", "redacted"
      )
      expect(cleaned.representation["redacted"]).to be(true)
      expect(cleaned.representation["metrics"]).to be_a(Hash)
      expect(cleaned.route_metadata).to eq({ "redacted" => true })
      expect(cleaned.sanitized_gpx_blob_id).to be_nil
      expect(cleaned.sanitized_route_image_blob_id).to be_nil
      expect(cleaned).to be_valid
      expect(Workouts::PublicationPreflight.new.call).to be_passed
    end

    it "purges sanitized blobs while preserving source attachments" do
      media_profile = create(
        :publishing_profile,
        :custom,
        :without_endpoint_masks,
        user: owner,
        settings: PublishingProfile::DEFAULT_SETTINGS.merge(
          "gpx" => true, "route_image" => true, "mask_start" => false, "mask_finish" => false
        )
      )
      media_workout = create(:workout, user: owner)
      create(:track_segment, workout: media_workout)
      media_workout.original_file.attach(
        io: StringIO.new("<gpx></gpx>"), filename: "source.gpx", content_type: "application/gpx+xml"
      )
      media_workout.route_image.attach(
        io: StringIO.new("png"), filename: "source.png", content_type: "image/png"
      )
      media_publication = publish_workout!(user: owner, workout: media_workout, profile: media_profile)
      sanitized_ids = [ media_publication.sanitized_gpx_blob_id, media_publication.sanitized_route_image_blob_id ]
      Workouts::PublicationWithdrawal.new(user: owner, workout: media_workout).call!
      settle_publication!(media_publication)

      described_class.new(publication: media_publication).call!

      expect(ActiveStorage::Blob.where(id: sanitized_ids)).to be_empty
      expect(media_workout.reload.original_file).to be_attached
      expect(media_workout.route_image).to be_attached
      expect(media_workout.track_segments).not_to be_empty
    end

    it "redacts payloads to a coordinate-free audit envelope with digests" do
      expected_digest = Federation::Outbox::CanonicalJson.digest(original_payload)

      described_class.new(publication:).call!

      redacted = create_event.reload
      expect(redacted.payload_digest).to eq(expected_digest)
      expect(redacted.payload_redacted_at).to be_present
      expect(redacted.payload).to include(
        "redacted" => true,
        "activity_uri" => create_event.activity_uri,
        "activity_type" => "Create",
        "actor" => owner.actor_uri,
        "object" => publication.object_uri,
        "payload_digest" => expected_digest
      )
      expect(redacted.payload["audience_digest"]).to be_present
      expect(redacted.payload.to_json).not_to include("6.4", "45.0", "LineString", "route-")
      expect(redacted.payload.keys).to contain_exactly(
        "redacted", "activity_uri", "activity_type", "actor", "object", "audience_digest", "payload_digest"
      )
    end

    it "is safe to repeat" do
      first = described_class.new(publication:).call!
      second = described_class.new(publication:).call!

      expect(first.cleaned).to be(true)
      expect(second.cleaned).to be(false)
      expect(second.publication.representation).to eq(first.publication.representation)
    end

    it "cleans publications whose source was already deleted" do
      publication.mark_deleted! if publication.active?
      workout.destroy!
      retained = WorkoutPublication.find(publication.id)
      expect(retained.workout_id).to be_nil
      settle_publication!(retained)

      result = described_class.new(publication: retained).call!

      expect(result.cleaned).to be(true)
      expect(result.publication.actor).to be_present
      expect(result.publication.object_uri).to eq(publication.object_uri)
    end
  end

  describe ".sweep" do
    it "cleans only eligible publications" do
      eligible, _delete_event = publish_and_withdraw!
      settle_publication!(eligible)
      blocked_workout = create(:workout, user: owner)
      create(:track_segment, workout: blocked_workout)
      blocked = publish_workout!(user: owner, workout: blocked_workout, profile:)

      cleaned = described_class.sweep

      expect(cleaned).to eq(1)
      expect(eligible.reload.location_data_purged_at).to be_present
      expect(blocked.reload.location_data_purged_at).to be_nil
    end
  end
end
