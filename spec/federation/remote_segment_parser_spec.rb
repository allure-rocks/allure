# frozen_string_literal: true

require "rails_helper"

RSpec.describe Federation::Parsers::RemoteSegment do
  def parse(activity = federation_segment_activity)
    described_class.new(activity).call
  end

  it "normalizes a valid course Note" do
    value = parse

    expect(value.object_uri).to eq(FederationNoteFixtures::SEGMENT_OBJECT_URI)
    expect(value.name).to eq("Col du Test")
    expect(value.sport_label).to eq("Cycling")
    expect(value.sport_slug).to eq("cycling")
    expect(value.published_at).to eq(Time.utc(2026, 8, 26, 12))
    expect(value.location).to eq("longitude" => 6.4, "latitude" => 45.0)
    expect(value.metrics).to include(
      "distance" => 2500.0,
      "ascent" => 180.0,
      "match_tolerance" => 25.0
    )
    expect(value.attachments.map(&:kind)).to contain_exactly("gpx", "route_image")
    expect(value.warnings).to be_empty
    expect(value.raw).to eq(federation_segment_activity["object"])
  end

  it "rejects a workout object path" do
    activity = federation_segment_activity
    activity["object"]["id"] = "https://remote.example/api/v1/trail/abc"

    expect { parse(activity) }
      .to raise_error(described_class::InvalidObject, /not a course/)
  end

  it "rejects a non-canonical segment short id" do
    activity = federation_segment_activity
    activity["object"]["id"] = "https://remote.example/api/v1/segment/not-a-short-id"

    expect { parse(activity) }
      .to raise_error(described_class::InvalidObject, /short id is invalid/)
  end

  it "requires the course kind tag" do
    activity = federation_segment_activity
    activity["object"]["tag"].reject! { |tag| tag["name"] == "segment_kind" }

    expect { parse(activity) }
      .to raise_error(described_class::InvalidObject, /kind is missing/)

    activity["object"]["tag"] << { "type" => "Note", "name" => "segment_kind", "content" => "route" }

    expect { parse(activity) }
      .to raise_error(described_class::InvalidObject, /kind is unsupported/)
  end

  it "requires a GPX attachment" do
    activity = federation_segment_activity
    activity["object"]["attachment"] = [
      { "type" => "Image", "mediaType" => "image/png", "url" => "#{FederationNoteFixtures::SEGMENT_OBJECT_URI}/media/route-image" }
    ]

    expect { parse(activity) }
      .to raise_error(described_class::InvalidObject, /no GPX attachment/)
  end

  it "rejects a course whose GPX is hosted on another authority" do
    activity = federation_segment_activity
    activity["object"]["attachment"] = [
      { "type" => "Document", "mediaType" => "application/xml+gpx",
        "url" => "https://victim.example/api/v1/segment/#{FederationNoteFixtures::SEGMENT_SHORT_ID}/media/gpx" }
    ]

    expect { parse(activity) }
      .to raise_error(described_class::InvalidObject, /no GPX attachment/)
  end

  it "skips a route image hosted on another authority" do
    activity = federation_segment_activity
    activity["object"]["attachment"] = [
      { "type" => "Document", "mediaType" => "application/xml+gpx",
        "url" => "#{FederationNoteFixtures::SEGMENT_OBJECT_URI}/media/gpx" },
      { "type" => "Image", "mediaType" => "image/png",
        "url" => "https://victim.example/api/v1/trail/xyz/media/route-image" }
    ]

    value = parse(activity)

    expect(value.attachments.map(&:kind)).to eq([ "gpx" ])
    expect(value.warnings).to include(a_string_matching(/attachment authority/))
  end

  it "requires a valid published timestamp" do
    activity = federation_segment_activity
    activity["object"].delete("published")

    expect { parse(activity) }
      .to raise_error(described_class::InvalidObject, /published is required/)

    activity["object"]["published"] = "2026-08-26 12:00:00"

    expect { parse(activity) }
      .to raise_error(described_class::InvalidObject, /published is invalid/)
  end

  it "matches the object and author authority" do
    activity = federation_segment_activity
    activity["object"]["attributedTo"] = "https://elsewhere.example/users/other"

    expect { parse(activity) }
      .to raise_error(described_class::InvalidObject, /attribution does not match/)
  end

  it "drops out-of-bounds course metrics with a warning" do
    activity = federation_segment_activity
    activity["object"]["tag"].find { |tag| tag["name"] == "match_tolerance" }["content"] = "500m"

    value = parse(activity)

    expect(value.metrics).not_to have_key("match_tolerance")
    expect(value.warnings.join).to include("metric out of range: match_tolerance")
  end

  it "treats an all-sports course as label and slug free" do
    activity = federation_segment_activity
    activity["object"]["tag"].reject! { |tag| %w[category sport_slug].include?(tag["name"]) }

    value = parse(activity)

    expect(value.sport_label).to be_nil
    expect(value.sport_slug).to be_nil
  end

  it "caps attachments and audience with warnings" do
    activity = federation_segment_activity
    activity["object"]["attachment"] = Array.new(6) do |index|
      { "type" => "Document", "mediaType" => "application/xml+gpx", "url" => "https://remote.example/gpx-#{index}" }
    end
    activity["object"]["to"] = Array.new(described_class::MAX_AUDIENCE + 1) { |index| "https://remote.example/audience/#{index}" }

    value = parse(activity)

    expect(value.attachments.length).to be <= described_class::MAX_ATTACHMENTS
    expect(value.audience.length).to eq(described_class::MAX_AUDIENCE)
    expect(value.warnings.join).to include("too many attachments", "too many audience entries")
  end

  it "reads the light and dark image variants from the theme property" do
    activity = federation_segment_activity
    activity["object"]["attachment"] = [
      { "type" => "Document", "mediaType" => "application/xml+gpx",
        "url" => "https://remote.example/api/v1/segment/abc/media/gpx" },
      { "type" => "Image", "mediaType" => "image/png",
        "url" => "https://remote.example/api/v1/segment/abc/media/route-image" },
      { "type" => "Image", "mediaType" => "image/png", "allure:theme" => "dark",
        "url" => "https://remote.example/api/v1/segment/abc/media/route-image-dark" }
    ]

    value = parse(activity)

    expect(value.attachments.map { |attachment| [ attachment.kind, attachment.theme ] })
      .to eq([ [ "gpx", "light" ], [ "route_image", "light" ], [ "route_image", "dark" ] ])
  end
end
