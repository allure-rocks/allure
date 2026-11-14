# frozen_string_literal: true

require "rails_helper"

RSpec.describe Federation::Serializers::SegmentNote do
  let(:user) { create(:user) }
  let(:segment) { create(:segment, user:, name: "Col du Test", description: "Le versant nord") }
  let(:publication) { create(:segment_publication, :with_gpx, segment:) }

  def note
    described_class.new(publication:, actor: publication.actor).call
  end

  it "serializes the course as a Note with the dedicated object identity" do
    expect(note).to include(
      "id" => publication.object_uri,
      "type" => "Note",
      "attributedTo" => publication.actor.uri,
      "name" => "Col du Test",
      "published" => publication.published_at.utc.iso8601
    )
    expect(note["url"]).to end_with("/segments/#{segment.to_param}")
    expect(note["location"]).to include("type" => "Place", "longitude" => 6.4074, "latitude" => 45.071)
  end

  it "carries the course tags and the GPX attachment, and no effort data" do
    tag_by_name = note["tag"].index_by { |tag| tag["name"] }

    expect(tag_by_name.dig("segment_kind", "content")).to eq("segment")
    expect(tag_by_name.dig("distance", "content")).to end_with("m")
    expect(tag_by_name.dig("match_tolerance", "content")).to eq("25.000000m")
    expect(tag_by_name).to have_key("category")
    expect(tag_by_name.dig("sport_slug", "content")).to eq(segment.sport.slug)
    expect(tag_by_name).to have_key("elevation_gain")

    attachment = note["attachment"].first
    expect(attachment).to include(
      "type" => "Document",
      "mediaType" => "application/xml+gpx",
      "name" => "GPX course"
    )
    expect(attachment["url"]).to eq("#{publication.object_uri}/media/gpx")
    expect(note.to_s).not_to match(/elapsed|anonymous|athlete|effort|alias|segment_index/)
  end

  it "omits the category tag for an all-sports course" do
    all_sports = create(:segment, user:, sport: nil)
    publication = create(:segment_publication, :with_gpx, segment: all_sports)

    names = described_class.new(publication:, actor: publication.actor).call["tag"].map { |tag| tag["name"] }

    expect(names).not_to include("category", "sport_slug")
    expect(names).to include("segment_kind")
  end

  it "addresses the followers collection for a followers audience" do
    publication = create(:segment_publication, :with_gpx, segment:, audience: "followers")

    result = described_class.new(publication:, actor: publication.actor).call

    expect(result["to"]).to eq([ "#{publication.actor.uri}/followers" ])
    expect(result["cc"]).to eq([])
  end

  it "advertises the dark course image after the light one" do
    light = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("\x89PNG\r\n\x1A\nlight".b), filename: "segment-light.png", content_type: "image/png"
    )
    dark = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("\x89PNG\r\n\x1A\ndark".b), filename: "segment-dark.png", content_type: "image/png"
    )
    publication.route_image.attach(light)
    publication.route_image_dark.attach(dark)
    SegmentPublication.where(id: publication.id).update_all(
      sanitized_route_image_blob_id: light.id,
      sanitized_route_image_dark_blob_id: dark.id
    )
    publication.reload

    images = note["attachment"].select { |attachment| attachment["type"] == "Image" }

    expect(images.map { |attachment| attachment["url"] }).to eq([
      "#{publication.object_uri}/media/route-image",
      "#{publication.object_uri}/media/route-image-dark"
    ])
    expect(images.last["allure:theme"]).to eq("dark")
  end

  it "is unavailable without an active publication or a sanitized course" do
    inactive = create(:segment_publication, :with_gpx, segment:, status: "deleted", deleted_at: Time.current)

    expect { described_class.new(publication: inactive, actor: inactive.actor).call }
      .to raise_error(described_class::Unavailable)

    without_gpx = create(:segment_publication, segment:)
    expect { described_class.new(publication: without_gpx, actor: without_gpx.actor).call }
      .to raise_error(described_class::Unavailable)
  end
end
