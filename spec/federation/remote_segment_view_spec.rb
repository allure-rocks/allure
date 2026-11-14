# frozen_string_literal: true

require "rails_helper"

RSpec.describe Federation::RemoteSegmentView do
  let(:sport) { catalog_sport("cycling") }
  let(:track) do
    {
      "type" => "FeatureCollection",
      "features" => [
        {
          "type" => "Feature",
          "geometry" => { "type" => "LineString", "coordinates" => [ [ 6.4, 45.0 ], [ 6.5, 45.1 ] ] },
          "properties" => { "segment_index" => 0 }
        }
      ]
    }
  end
  let(:segment) do
    create(
      :remote_segment,
      representation: {
        "name" => "Col du Test",
        "sport_slug" => "cycling",
        "kind" => "segment",
        "distance" => 2500.0,
        "ascent" => 180.0,
        "track" => track
      }
    )
  end

  before { sport }

  def set_representation(value)
    RemoteSegment.where(id: segment.id).update_all(representation: value)
    segment.reload
  end

  it "projects the course metrics and resolves the sport by slug" do
    view = described_class.new(segment)

    expect(view.name).to eq("Col du Test")
    expect(view.sport).to eq(sport)
    expect(view.all_sports?).to be(false)
    expect(view.distance).to eq(2500.0)
    expect(view.metric_visible?(:distance)).to be(true)
    expect(view.metric_visible?(:duration)).to be(false)
    expect(view.metrics_present?).to be(true)
    expect(view.map_visible?).to be(true)
    expect(view.points_count).to be_nil
  end

  it "uses the all-sports fallback when the slug is absent" do
    RemoteSegment.where(id: segment.id).update_all(sport_label: nil)
    set_representation(segment.representation.except("sport_slug"))

    view = described_class.new(segment)

    expect(view.all_sports?).to be(true)
    expect(view.sport.pace_speed_display).to eq("speed")
    expect(view.sport.translated_name).to eq(I18n.t("segments.details.all_sports"))
  end

  it "keeps the label with a neutral glyph when the slug is unknown" do
    set_representation(segment.representation.merge("sport_slug" => "unicycle"))

    view = described_class.new(segment)

    expect(view.sport.slug).to eq("remote")
    expect(view.sport.icon).to eq("sports/icons/families/other")
  end

  it "reports the media states and copyability" do
    view = described_class.new(segment)

    expect(view.media_pending?).to be(false)
    expect(view.media_unavailable?).to be(false)
    expect(view.copyable?).to be(false)

    create(:remote_segment_attachment, remote_segment: segment, kind: "gpx", status: "pending")
    expect(described_class.new(segment).media_pending?).to be(true)
    expect(described_class.new(segment).media_unavailable?).to be(false)

    attachment = segment.attachments.first
    attachment.update!(status: "cached", blob_id: create_blob.id)
    expect(described_class.new(segment).copyable?).to be(true)
    expect(described_class.new(segment).map_visible?).to be(true)
  end

  def create_blob
    ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("gpx"),
      filename: "course.gpx",
      content_type: "application/gpx+xml"
    )
  end
end
