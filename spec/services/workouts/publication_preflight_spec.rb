# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workouts::PublicationPreflight do
  let(:owner) { create(:user) }
  let!(:actor) { create(:local_actor, user: owner) }
  let(:workout) { create(:workout, user: owner) }
  let!(:publication) { create(:workout_publication, workout:) }
  let!(:create_event) do
    create(
      :federation_outbox_event,
      actor:,
      subject_type: "WorkoutPublication",
      subject_id: publication.id,
      activity_type: "Create",
      object_uri: publication.object_uri
    )
  end

  describe "#call" do
    it "passes for valid publication, actor, outbox, and attachment state" do
      result = described_class.new.call

      expect(result).to be_passed
      expect(result.publication_count).to eq(1)
      expect(result.issues).to be_empty
    end

    it "accepts a scheduled publication with no outbox activity" do
      create(:workout_publication, :scheduled)

      result = described_class.new.call

      expect(result).to be_passed
    end

    it "reports a scheduled publication that carries outbox activity" do
      scheduled = create(:workout_publication, :scheduled)
      create(
        :federation_outbox_event,
        actor: scheduled.actor,
        subject_type: "WorkoutPublication",
        subject_id: scheduled.id,
        workout_publication_id: scheduled.id,
        activity_type: "Create",
        object_uri: scheduled.object_uri
      )

      result = described_class.new.call

      expect(result.issues.map(&:code)).to include(:scheduled_publication_with_outbox)
    end

    it "accepts a valid segment publication outbox event" do
      segment = create(:segment, user: owner, visibility: "public")
      segment_publication = create(:segment_publication, :with_gpx, segment:, actor:)
      create(
        :federation_outbox_event,
        actor:,
        subject_type: "SegmentPublication",
        subject_id: segment_publication.id,
        segment_publication_id: segment_publication.id,
        activity_type: "Create",
        object_uri: segment_publication.object_uri
      )

      result = described_class.new.call

      expect(result.issues.map(&:code))
        .not_to include(:unsupported_outbox_subject, :dangling_segment_publication_outbox_subject)
    end

    # Local followers read it whatever the restricted switch says.
    it "accepts and validates an active followers-only publication" do
      WorkoutPublication.where(id: publication.id).update_all(
        profile_snapshot: publication.profile_snapshot.merge("audience" => "followers")
      )

      result = described_class.new.call

      expect(result).to be_passed
    end

    it "reports a retained actor that is tombstoned" do
      actor.update_columns(user_id: nil, tombstoned_at: Time.current)

      result = described_class.new.call

      expect(result.issues.map(&:code)).to include(:publication_invalid_local_actor)
    end

    it "reports a publication outbox event whose object URI does not match its publication" do
      FederationOutboxEvent.where(id: create_event.id).update_all(object_uri: "https://example.test/mismatched")

      result = described_class.new.call

      expect(result.issues.map(&:code)).to include(:publication_outbox_identity_mismatch)
    end

    it "reports a direct blob reference without a matching attachment" do
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("<?xml version=\"1.0\"?><gpx />"),
        filename: "sanitized.gpx",
        content_type: "application/gpx+xml"
      )
      WorkoutPublication.where(id: publication.id).update_all(sanitized_gpx_blob_id: blob.id)

      result = described_class.new.call

      expect(result.issues.map(&:code)).to include(:publication_attachment_count_mismatch)
    end

    it "reports an attachment without a matching direct blob reference" do
      publication.gpx.attach(
        io: StringIO.new("<?xml version=\"1.0\"?><gpx />"),
        filename: "sanitized.gpx",
        content_type: "application/gpx+xml"
      )

      result = described_class.new.call

      expect(result.issues.map(&:code)).to include(:publication_attachment_without_reference)
    end

    it "reports an invalid retained representation" do
      WorkoutPublication.where(id: publication.id).update_all(representation: { "private" => "source" })

      result = described_class.new.call

      expect(result.issues.map(&:code)).to include(:invalid_retained_publication)
    end

    it "is repeatable and does not change persisted state" do
      before_counts = {
        publications: WorkoutPublication.count,
        events: FederationOutboxEvent.count,
        attachments: ActiveStorage::Attachment.count,
        blobs: ActiveStorage::Blob.count
      }

      first = described_class.new.call
      second = described_class.new.call

      expect(second).to eq(first)
      expect({
        publications: WorkoutPublication.count,
        events: FederationOutboxEvent.count,
        attachments: ActiveStorage::Attachment.count,
        blobs: ActiveStorage::Blob.count
      }).to eq(before_counts)
    end
  end
end
