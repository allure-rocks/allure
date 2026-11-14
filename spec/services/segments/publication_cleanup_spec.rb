# frozen_string_literal: true

require "rails_helper"

RSpec.describe Segments::PublicationCleanup do
  let(:segment) { create(:segment, visibility: "public") }

  it "redacts and purges an eligible deleted publication" do
    publication = create(:segment_publication, :with_gpx, segment:, status: "deleted", deleted_at: Time.current)

    result = described_class.new(publication:).call!

    expect(result.cleaned).to be(true)
    publication.reload
    expect(publication.representation["redacted"]).to be(true)
    expect(publication.representation["track"]).to be_nil
    expect(publication.location_data_purged_at).to be_present
    expect(publication.gpx).not_to be_attached
    expect(publication.sanitized_gpx_blob_id).to be_nil
  end

  it "refuses while a related outbox event is not terminal" do
    publication = create(:segment_publication, :with_gpx, segment:, status: "deleted", deleted_at: Time.current)
    create(
      :federation_outbox_event,
      actor: publication.actor,
      subject_type: "SegmentPublication",
      subject_id: publication.id,
      segment_publication_id: publication.id,
      activity_type: "Create",
      object_uri: publication.object_uri,
      status: "pending"
    )

    expect(described_class.eligible?(publication)).to be(false)
    expect { described_class.new(publication:).call! }.to raise_error(described_class::NotEligible)
  end

  it "is a no-op for an active publication" do
    publication = create(:segment_publication, :with_gpx, segment:)

    expect(described_class.eligible?(publication)).to be(false)
  end
end
