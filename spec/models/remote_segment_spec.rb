# frozen_string_literal: true

require "rails_helper"

RSpec.describe RemoteSegment do
  it "accepts the factory" do
    expect(build(:remote_segment)).to be_valid
  end

  it "requires an absolute object and activity URI matching the author" do
    segment = build(:remote_segment, object_uri: "not a uri")

    expect(segment).not_to be_valid
    expect(segment.errors[:object_uri]).to be_present

    segment = build(:remote_segment)
    segment.source_domain = "elsewhere.example"

    expect(segment).not_to be_valid
    expect(segment.errors[:source_domain]).to be_present
  end

  it "requires the course kind and a valid active representation" do
    segment = build(:remote_segment, kind: "route")

    expect(segment).not_to be_valid

    segment = build(:remote_segment)
    segment.representation = segment.representation.except("name")

    expect(segment).not_to be_valid
    expect(segment.errors[:representation]).to be_present
  end

  it "requires exactly one LineString feature" do
    segment = build(:remote_segment)
    feature = {
      "type" => "Feature",
      "geometry" => { "type" => "LineString", "coordinates" => [ [ 6.4, 45.0 ], [ 6.5, 45.1 ] ] },
      "properties" => { "segment_index" => 0 }
    }
    segment.representation = segment.representation.merge(
      "track" => { "type" => "FeatureCollection", "features" => [ feature, feature ] }
    )

    expect(segment).not_to be_valid

    segment.representation = segment.representation.merge(
      "track" => { "type" => "FeatureCollection", "features" => [ feature ] }
    )

    expect(segment).to be_valid
  end

  it "keeps identity and representation columns immutable" do
    segment = create(:remote_segment)

    expect { segment.update!(representation: { "redacted" => true }) }
      .to raise_error(ActiveRecord::ReadonlyAttributeError)
  end

  it "allows a nameless tombstone" do
    expect(create(:remote_segment, :deleted)).to be_deleted
  end

  describe "#entitled_to?" do
    it "follows the active entitlement" do
      segment = create(:remote_segment)
      recipient = create(:remote_segment_recipient, remote_segment: segment)

      expect(segment.entitled_to?(recipient.recipient_actor)).to be(true)

      recipient.withdraw!(reason: "unfollow", at: Time.current)

      expect(segment.reload.entitled_to?(recipient.recipient_actor)).to be(false)
    end
  end

  describe "#attach_remote_media!" do
    it "merges the track and ignores the chart" do
      segment = create(:remote_segment)
      track = {
        "type" => "FeatureCollection",
        "features" => [
          {
            "type" => "Feature",
            "geometry" => { "type" => "LineString", "coordinates" => [ [ 6.4, 45.0 ], [ 6.5, 45.1 ] ] },
            "properties" => { "segment_index" => 0 }
          }
        ]
      }

      segment.attach_remote_media!(
        track:,
        chart: [ { "distance" => 1 } ],
        route_metadata: { "bounds" => [ 6.4, 45.0, 6.5, 45.1 ], "segments_count" => 1 }
      )

      expect(segment.reload.representation["track"]).to eq(track)
      expect(segment.representation).not_to have_key("chart")
      expect(segment.route_metadata["segments_count"]).to eq(1)
    end

    it "is a no-op after deletion" do
      segment = create(:remote_segment, :deleted)

      expect(segment.attach_remote_media!(track: {}, route_metadata: {})).to eq(segment)
      expect(segment.reload.representation).to eq("redacted" => true)
    end
  end
end
