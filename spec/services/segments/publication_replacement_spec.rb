# frozen_string_literal: true

require "rails_helper"

RSpec.describe Segments::PublicationReplacement do
  let(:user) { create(:user) }
  let(:segment) { create(:segment, user:, visibility: "public") }
  let(:old_publication) { Segments::Publisher.new(user:, segment:).call! }

  before { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }
  after { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }

  it "creates a new identity and withdraws the old one in one intent pair" do
    old = old_publication
    segment.update!(name: "Nouveau nom")
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear

    result = described_class.new(user:, segment:).call!

    expect(result.old_publication).to be_deleted
    expect(result.new_publication).to be_active
    expect(result.new_publication.object_uri).not_to eq(old.object_uri)
    expect(result.new_publication.representation["name"]).to eq("Nouveau nom")
    expect(result.delete_event).to have_attributes(
      subject_type: "SegmentPublication",
      object_uri: old.object_uri,
      activity_type: "Delete"
    )
    expect(result.create_event).to be_preparing
    expect(FederationOutboxEvent.where(activity_type: "Update").count).to be_zero
    expect(Segments::RenderPublicationRouteImageJob).to have_been_enqueued
  end

  it "refuses when no active publication exists" do
    expect { described_class.new(user:, segment:).call! }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "leaves the old publication active when preparation fails" do
    old = old_publication
    create(:privacy_zone, user:)
    segment.update_columns(privacy_zone_acknowledged_at: nil)

    expect do
      described_class.new(user:, segment:).call!
    end.to raise_error(Segments::Publisher::PublicationError, I18n.t("segments.publish.errors.corridor_acknowledgment"))

    expect(old.reload).to be_active
    expect(segment.reload.active_publication).to eq(old)
  end

  it "rejects non-owners" do
    old_publication
    other = create(:user)

    expect { described_class.new(user: other, segment:).call! }.to raise_error(ActiveRecord::RecordNotFound)
  end
end
