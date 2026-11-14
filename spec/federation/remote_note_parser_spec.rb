# frozen_string_literal: true

require "rails_helper"

RSpec.describe Federation::Parsers::RemoteNote do
  def note_activity(overrides = {})
    {
      "id" => "https://remote.example/api/v1/trail/abc/activities/create-1",
      "type" => "Create",
      "actor" => "https://remote.example/users/demo",
      "object" => {
        "id" => "https://remote.example/api/v1/trail/abc",
        "type" => "Note",
        "attributedTo" => "https://remote.example/users/demo",
        "name" => "Morning hike",
        "content" => "Morning hike<br>A short description",
        "startTime" => "2026-08-26T12:00:00Z",
        "published" => "2026-08-26T12:00:00Z",
        "location" => { "type" => "Place", "longitude" => 6.4, "latitude" => 45.0 },
        "to" => [ "https://www.w3.org/ns/activitystreams#Public" ],
        "cc" => [ "https://remote.example/users/demo/followers" ],
        "tag" => [
          { "type" => "Note", "name" => "category", "content" => "Hiking" },
          { "type" => "Note", "name" => "distance", "content" => "23064.640055m" },
          { "type" => "Note", "name" => "elevation_gain", "content" => "1009.000000m" },
          { "type" => "Note", "name" => "duration", "content" => "22345.000000m" }
        ],
        "attachment" => [
          { "type" => "Document", "mediaType" => "application/xml+gpx",
            "url" => "https://remote.example/api/v1/trail/abc/media/gpx" }
        ]
      },
      "to" => [ "https://www.w3.org/ns/activitystreams#Public" ],
      "cc" => [ "https://remote.example/users/demo/followers" ]
    }.merge(overrides)
  end

  def parse(activity = note_activity)
    described_class.new(activity).call
  end

  it "normalizes the documented Allure tag profile" do
    value = parse

    expect(value.title).to eq("Morning hike")
    expect(value.sport_label).to eq("Hiking")
    expect(value.metrics).to eq(
      "distance" => 23_064.640055,
      "ascent" => 1009.0,
      "duration" => 22_345.0
    )
    expect(value.description).to eq("Morning hike A short description")
    expect(value.content_html).to eq("Morning hike<br>A short description")
    expect(value.started_at).to eq(Time.utc(2026, 8, 26, 12))
    expect(value.location).to eq("longitude" => 6.4, "latitude" => 45.0)
    expect(value.attachments.map(&:kind)).to eq([ "gpx" ])
    expect(value.warnings).to be_empty
  end

  it "accepts a grade-adjusted pace tag" do
    activity = note_activity
    activity["object"]["tag"] << { "type" => "Note", "name" => "grade_adjusted_pace", "content" => "187.000000" }

    expect(parse(activity).metrics.fetch("grade_adjusted_pace")).to eq(187.0)
  end

  it "skips an out-of-range grade-adjusted pace with a warning" do
    activity = note_activity
    activity["object"]["tag"] << { "type" => "Note", "name" => "grade_adjusted_pace", "content" => "999999" }

    value = parse(activity)

    expect(value.metrics).not_to have_key("grade_adjusted_pace")
    expect(value.warnings.join).to match(/out of range.*grade_adjusted_pace/m)
  end

  it "parses record marker tags with allowlisted tokens" do
    activity = note_activity
    activity["object"]["tag"] << { "type" => "Note", "name" => "record_types", "content" => "FD,HA,FD,ZZ" }
    activity["object"]["tag"] << { "type" => "Note", "name" => "record_distances", "content" => "km5, m400 ,bogus" }

    value = parse(activity)

    expect(value.record_types).to eq(%w[FD HA])
    expect(value.record_distances).to eq(%w[km5 m400])
    expect(value.warnings.join).to match(/invalid record_types token/)
    expect(value.warnings.join).to match(/invalid record_distances token/)
  end

  it "ignores a record tag whose content is not a string" do
    activity = note_activity
    activity["object"]["tag"] << { "type" => "Note", "name" => "record_types", "content" => 12 }

    expect(parse(activity).record_types).to eq([])
  end

  it "parses the recording device tag and bounds an oversized value" do
    activity = note_activity
    activity["object"]["tag"] << { "type" => "Note", "name" => "device", "content" => "  Garmin Edge 530  " }

    expect(parse(activity).device).to eq("Garmin Edge 530")

    oversized = note_activity
    oversized["object"]["tag"] << { "type" => "Note", "name" => "device", "content" => "x" * 400 }
    value = parse(oversized)

    expect(value.device.length).to eq(described_class::MAX_DEVICE)
    expect(value.warnings).to include(a_string_matching(/device truncated/))
  end

  it "ignores a device tag whose content is not a string" do
    activity = note_activity
    activity["object"]["tag"] << { "type" => "Note", "name" => "device", "content" => 12 }

    expect(parse(activity).device).to be_nil
  end

  it "parses a presence commute tag and understands explicit booleans" do
    activity = note_activity
    activity["object"]["tag"] << { "type" => "Note", "name" => "commute", "content" => "true" }
    expect(parse(activity).commute).to be(true)

    explicit_false = note_activity
    explicit_false["object"]["tag"] << { "type" => "Note", "name" => "commute", "content" => "0" }
    expect(parse(explicit_false).commute).to be(false)

    expect(parse(note_activity).commute).to be_nil
  end

  it "ignores a malformed commute tag with a warning" do
    activity = note_activity
    activity["object"]["tag"] << { "type" => "Note", "name" => "commute", "content" => "maybe" }
    value = parse(activity)

    expect(value.commute).to be_nil
    expect(value.warnings).to include(a_string_matching(/invalid commute value/))
  end

  it "reads comments closed by the origin's profile and keeps them open otherwise" do
    closed = note_activity
    closed["object"]["tag"] << { "type" => "Note", "name" => "comments", "content" => "closed" }
    expect(parse(closed).comments_closed).to be(true)

    open = note_activity
    open["object"]["tag"] << { "type" => "Note", "name" => "comments", "content" => "open" }
    expect(parse(open).comments_closed).to be_nil
    expect(parse(note_activity).comments_closed).to be_nil

    malformed = note_activity
    malformed["object"]["tag"] << { "type" => "Note", "name" => "comments", "content" => "maybe" }
    value = parse(malformed)
    expect(value.comments_closed).to be_nil
    expect(value.warnings).to include(a_string_matching(/invalid comments value/))
  end

  it "keeps the first duplicate metric and records a warning" do
    activity = note_activity
    activity["object"]["tag"] << { "type" => "Note", "name" => "distance", "content" => "1m" }

    value = parse(activity)

    expect(value.metrics.fetch("distance")).to eq(23_064.640055)
    expect(value.warnings).to include(a_string_matching(/duplicate metric/))
  end

  it "skips malformed and out-of-range metrics with warnings" do
    activity = note_activity
    activity["object"]["tag"] += [
      { "type" => "Note", "name" => "average_heart_rate", "content" => "abc" },
      { "type" => "Note", "name" => "calories", "content" => "-5" },
      { "type" => "Note", "name" => "not_a_metric", "content" => "1" }
    ]

    value = parse(activity)

    expect(value.metrics).not_to have_key("average_heart_rate")
    expect(value.metrics).not_to have_key("calories")
    expect(value.metrics).not_to have_key("not_a_metric")
    expect(value.warnings.join).to match(/malformed metric.*average_heart_rate/m)
    expect(value.warnings.join).to match(/out of range.*calories/m)
  end

  it "ignores Mention tags and preserves unknown tags in raw" do
    activity = note_activity
    activity["object"]["tag"] << {
      "id" => "https://remote.example/users/other", "type" => "Mention",
      "name" => "@other@remote.example", "href" => "https://remote.example/users/other"
    }

    value = parse(activity)

    expect(value.metrics.keys).not_to include("Mention")
    expect(value.raw.fetch("tag").last.fetch("type")).to eq("Mention")
  end

  it "sanitizes scripts and disallowed markup" do
    activity = note_activity
    activity["object"]["content"] = "Hello <script>alert(1)</script><img src=x><strong>there</strong>"

    value = parse(activity)

    expect(value.content_html).to eq("Hello alert(1)<strong>there</strong>")
    expect(value.content_html).not_to include("<script", "<img")
  end

  it "rejects space-separated and invalid timestamps with warnings" do
    activity = note_activity
    activity["object"]["published"] = "2026-08-26 12:00:00Z"
    activity["object"]["startTime"] = "not-a-time"

    value = parse(activity)

    expect(value.published_at).to be_nil
    expect(value.started_at).to be_nil
    expect(value.warnings).to include(a_string_matching(/invalid published/), a_string_matching(/invalid startTime/))
  end

  it "ignores a location with only one coordinate" do
    activity = note_activity
    activity["object"]["location"] = { "latitude" => 45.0 }

    value = parse(activity)

    expect(value.location).to be_nil
    expect(value.warnings).to include(a_string_matching(/invalid location/))
  end

  it "skips an attachment hosted on another authority" do
    activity = note_activity
    activity["object"]["attachment"] = [
      { "type" => "Document", "mediaType" => "application/xml+gpx",
        "url" => "https://victim.example/api/v1/trail/xyz/media/gpx" },
      { "type" => "Image", "mediaType" => "image/png",
        "url" => "https://remote.example:8443/api/v1/trail/abc/media/route-image" },
      { "type" => "Image", "mediaType" => "image/png",
        "url" => "https://REMOTE.example/api/v1/trail/abc/media/route-image" }
    ]

    value = parse(activity)

    expect(value.attachments.map(&:kind)).to eq([ "route_image" ])
    expect(value.attachments.first.remote_url).to eq("https://REMOTE.example/api/v1/trail/abc/media/route-image")
    expect(value.warnings.count { |warning| warning.match?(/attachment authority/) }).to eq(2)
  end

  it "normalizes string audiences and caps attachments" do
    activity = note_activity
    activity["to"] = "https://www.w3.org/ns/activitystreams#Public"
    activity["object"]["attachment"] = Array.new(6) do |index|
      { "type" => "Image", "mediaType" => "image/png",
        "url" => "https://remote.example/media/#{index}.png" }
    end

    value = parse(activity)

    expect(value.audience).to include("https://www.w3.org/ns/activitystreams#Public")
    expect(value.attachments.length).to eq(1)
    expect(value.warnings).to include(a_string_matching(/too many attachments/))
  end

  it "caps the audience at 200 entries and records a warning" do
    activity = note_activity
    activity["cc"] = Array.new(250) { |index| "https://remote.example/users/follower-#{index}" }

    value = parse(activity)

    expect(value.audience.length).to eq(200)
    expect(value.warnings).to include(a_string_matching(/too many audience entries/))
  end

  it "rejects a note whose authority differs from its attributed actor" do
    activity = note_activity
    activity["object"]["id"] = "https://other.example/api/v1/trail/abc"

    expect { parse(activity) }.to raise_error(described_class::InvalidObject, /authority/)
  end

  it "rejects a course object on the dedicated segment path" do
    activity = note_activity
    activity["object"]["id"] = FederationNoteFixtures::SEGMENT_OBJECT_URI

    expect { parse(activity) }.to raise_error(described_class::InvalidObject, /not a workout/)
  end

  it "rejects missing objects, wrong types, and misattribution" do
    expect { parse(note_activity("object" => nil)) }
      .to raise_error(described_class::InvalidObject, /embedded/)
    expect { parse(note_activity("object" => { "id" => "https://remote.example/x", "type" => "Article" })) }
      .to raise_error(described_class::InvalidObject, /type must be Note/)
    expect { parse(note_activity("object" => note_activity["object"].merge("attributedTo" => "https://remote.example/users/other"))) }
      .to raise_error(described_class::InvalidObject, /attribution/)
    expect { parse(note_activity("object" => note_activity["object"].except("name"))) }
      .to raise_error(described_class::InvalidObject, /name/)
  end

  it "truncates an oversized title with a warning" do
    activity = note_activity
    activity["object"]["name"] = "x" * 400

    value = parse(activity)

    expect(value.title.length).to eq(described_class::MAX_TITLE)
    expect(value.warnings).to include(a_string_matching(/title truncated/))
  end

  it "reads the light and dark image variants from the theme property" do
    activity = note_activity
    activity["object"]["attachment"] = [
      { "type" => "Image", "mediaType" => "image/png",
        "url" => "https://remote.example/api/v1/trail/abc/media/route-image" },
      { "type" => "Image", "mediaType" => "image/png", "allure:theme" => "dark",
        "url" => "https://remote.example/api/v1/trail/abc/media/route-image-dark" }
    ]

    value = parse(activity)

    expect(value.attachments.map { |attachment| [ attachment.kind, attachment.theme ] })
      .to eq([ [ "route_image", "light" ], [ "route_image", "dark" ] ])
  end

  it "degrades an unknown attachment theme to light with a warning" do
    activity = note_activity
    activity["object"]["attachment"] = [
      { "type" => "Image", "mediaType" => "image/png", "allure:theme" => "sepia",
        "url" => "https://remote.example/api/v1/trail/abc/media/route-image" }
    ]

    value = parse(activity)

    expect(value.attachments.first.theme).to eq("light")
    expect(value.warnings).to include(a_string_matching(/attachment theme/))
  end
end
