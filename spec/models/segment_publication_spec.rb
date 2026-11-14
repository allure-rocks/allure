# frozen_string_literal: true

require "rails_helper"

RSpec.describe SegmentPublication do
  let(:segment) { create(:segment, visibility: "public") }
  let(:publication) { create(:segment_publication, segment:) }

  describe "identity" do
    it "exposes the immutable object URI derived from its ShortUUID" do
      expect(publication.object_uri)
        .to eq(Allure::Federation.config.segment_publication_uri(publication.to_param))
      expect(described_class.find_by_short_id!(publication.to_param)).to eq(publication)
    end

    it "treats identity and representation columns as readonly" do
      expect { publication.update!(representation: publication.representation.merge("name" => "Hacked")) }
        .to raise_error(ActiveRecord::ReadonlyAttributeError)
      expect { publication.update!(object_uri: "https://evil.example/segment/x") }
        .to raise_error(ActiveRecord::ReadonlyAttributeError)
    end
  end

  describe "validations" do
    it "requires the source segment while active" do
      expect(build(:segment_publication, segment: nil)).not_to be_valid
    end

    it "allows a deleted publication whose source is gone" do
      deleted = build(:segment_publication, segment: nil, status: "deleted", deleted_at: Time.current)

      expect(deleted).to be_valid
    end

    it "allows only the course representation keys" do
      invalid = build(:segment_publication, segment:)
      invalid.representation = invalid.representation.merge("elapsed_time" => 10)

      expect(invalid).not_to be_valid
      expect(invalid.errors[:representation]).to be_present
    end

    it "requires exactly one LineString feature" do
      invalid = build(:segment_publication, segment:)
      feature = invalid.representation.dig("track", "features", 0)
      invalid.representation = invalid.representation.merge(
        "track" => { "type" => "FeatureCollection", "features" => [ feature, feature ] }
      )

      expect(invalid).not_to be_valid
    end

    it "validates the course metrics" do
      invalid = build(:segment_publication, segment:)
      invalid.representation = invalid.representation.merge("match_tolerance" => 500)

      expect(invalid).not_to be_valid
    end

    it "keeps one active publication per segment" do
      publication
      second = build(:segment_publication, segment:)

      expect(second).not_to be_valid
      expect(second.errors[:segment_id]).to be_present
    end

    it "rejects an actor that does not own the segment" do
      other_actor = create(:local_actor)
      invalid = build(:segment_publication, segment:, actor: other_actor)

      expect(invalid).not_to be_valid
    end
  end

  describe "#mark_deleted!" do
    it "is terminal, stamps the deletion, and resets the segment association" do
      publication
      segment.association(:active_publication).reset
      expect(segment.active_publication).to eq(publication)

      publication.mark_deleted!

      expect(publication).to be_deleted
      expect(publication.deleted_at).to be_present
      segment.association(:active_publication).reset
      expect(segment.active_publication).to be_nil
    end
  end
end
