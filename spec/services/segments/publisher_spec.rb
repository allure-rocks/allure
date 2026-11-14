# frozen_string_literal: true

require "rails_helper"

RSpec.describe Segments::Publisher do
  let(:user) { create(:user) }
  let(:segment) { create(:segment, user:, visibility: "public") }

  before { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }
  after { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }

  def publish
    described_class.new(user:, segment:).call!
  end

  describe "a public course" do
    it "creates an immutable publication with its Create intent preparing for the route image" do
      publication = nil

      expect { publication = publish }.to change(SegmentPublication, :count).by(1)
      expect(Segments::RenderPublicationRouteImageJob).to have_been_enqueued
      expect(Federation::ExpandOutboxEventJob).not_to have_been_enqueued

      expect(publication).to have_attributes(
        segment:,
        audience: "public",
        status: "active",
        route_image_pending?: true
      )
      expect(publication.object_uri)
        .to eq(Allure::Federation.config.segment_publication_uri(publication.to_param))
      expect(publication.sanitized_attachment(:gpx)).to be_present
      expect(publication.source_fingerprint).to eq(segment.publication_fingerprint)

      event = FederationOutboxEvent.find_by(segment_publication_id: publication.id, activity_type: "Create")
      expect(event).to have_attributes(
        subject_type: "SegmentPublication",
        subject_id: publication.id,
        status: "preparing"
      )
      expect(event.payload.dig("object", "id")).to eq(publication.object_uri)
    end

    it "carries no effort, athlete, or activity-time data in the representation" do
      publication = publish

      expect(publication.representation.keys - SegmentPublication::REPRESENTATION_KEYS).to be_empty
      expect(publication.representation.to_s).not_to match(/elapsed|anonymous|athlete|started_at|efforts/)
      expect(publication.track.dig("features", 0, "properties")).to eq("segment_index" => 0)
    end

    it "rejects a second publication while one is active" do
      publish

      expect { publish }
        .to raise_error(Segments::Publisher::PublicationError, I18n.t("segments.publish.errors.already_published"))
    end
  end

  describe "a private course" do
    let(:segment) { create(:segment, user:) }

    it "refuses to publish" do
      expect { publish }
        .to raise_error(Segments::Publisher::PublicationError, I18n.t("segments.publish.errors.not_shareable"))
      expect(SegmentPublication.count).to be_zero
    end
  end

  describe "a followers-only course" do
    let(:segment) { create(:segment, user:, visibility: "followers_only") }

    %w[false true].each do |restricted|
      it "publishes a followers audience with restricted federation #{restricted}" do
        allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(restricted == "true")

        expect(publish.audience).to eq("followers")
      end
    end

    it "addresses its Create to the followers collection only" do
      allow(Allure::Federation::Config).to receive(:restricted_enabled?).and_return(true)

      publication = publish

      expect(publication.audience).to eq("followers")
      event = FederationOutboxEvent.find_by(segment_publication_id: publication.id, activity_type: "Create")
      expect(event.audience.values.flatten.join).to include("#{user.actor_uri}/followers")
      expect(event.audience.values.flatten.join).not_to include("#Public")
    end
  end

  describe "a corridor through an active privacy zone" do
    # The segment is created while the owner has no zone, then the zone appears.
    before { segment }

    it "requires the stored acknowledgment" do
      create(:privacy_zone, user:)
      segment.update_columns(privacy_zone_acknowledged_at: nil)

      expect { publish }
        .to raise_error(Segments::Publisher::PublicationError, I18n.t("segments.publish.errors.corridor_acknowledgment"))
    end

    it "publishes once acknowledged" do
      create(:privacy_zone, user:)
      segment.update_columns(privacy_zone_acknowledged_at: Time.current)

      expect { publish }.to change(SegmentPublication, :count).by(1)
    end
  end

  it "refuses another user's segment" do
    other = create(:segment, visibility: "public")

    expect { described_class.new(user:, segment: other).call! }
      .to raise_error(ActiveRecord::RecordNotFound)
  end
end
