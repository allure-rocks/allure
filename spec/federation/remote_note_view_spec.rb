# frozen_string_literal: true

require "rails_helper"

RSpec.describe Federation::RemoteNoteView do
  let(:representation) do
    {
      "title" => "Morning hike",
      "description" => "A short description",
      "sport_label" => "Hiking",
      "started_at" => "2026-08-26T12:00:00Z",
      "metrics" => { "distance" => 1234.5, "ascent" => 100.0 },
      "track" => {
        "type" => "FeatureCollection",
        "features" => [
          { "type" => "Feature",
            "geometry" => { "type" => "LineString", "coordinates" => [ [ 6.4, 45.0 ], [ 6.5, 45.1 ] ] },
            "properties" => { "segment_index" => 0 } }
        ]
      },
      "chart" => [ { "distance" => 0.0, "elapsed_time" => nil, "elevation" => 100.0 } ]
    }
  end
  let(:note) do
    create(:remote_note, title: "Morning hike", description: "A short description",
                         sport_label: "Hiking", metrics: representation["metrics"], representation:)
  end

  subject(:view) { described_class.new(note) }

  it "projects the stored representation" do
    expect(view.title).to eq("Morning hike")
    expect(view.description).to eq("A short description")
    expect(view.started_at).to eq(Time.utc(2026, 8, 26, 12))
    expect(view.metric_visible?(:distance)).to be(true)
    expect(view.metric_visible?(:calories)).to be(false)
    expect(view.distance).to eq(1234.5)
    expect(view.metrics_present?).to be(true)
    expect(view.map_visible?).to be(true)
    expect(view.chart_visible?).to be(true)
  end

  it "exposes published record markers" do
    marked = create(:remote_note, representation: representation.merge(
      "record_types" => %w[FD HA], "record_distances" => %w[km5]
    ))

    view = described_class.new(marked)

    expect(view.record_types).to eq(%w[FD HA])
    expect(view.record_distances).to eq(%w[km5])
  end

  it "exposes the shared recording device when present" do
    with_device = create(:remote_note, representation: representation.merge("device" => "Garmin Edge 530"))

    expect(described_class.new(with_device).device).to eq("Garmin Edge 530")
    expect(view.device).to be_nil
  end

  it "exposes the commute flag when present" do
    commute = create(:remote_note, representation: representation.merge("commute" => true))

    expect(described_class.new(commute).commute).to be(true)
    expect(view.commute).to be(false)
  end

  it "says whether the origin closed comments" do
    closed = create(:remote_note, representation: representation.merge("comments_closed" => true))

    expect(described_class.new(closed).comments_closed?).to be(true)
    expect(view.comments_closed?).to be(false)
  end

  it "matches the remote sport label to the shared catalog" do
    # A freshly prepared test database is seeded, so the catalog may already
    # hold "Hiking"; only create a test-local sport when it does not.
    sport = Sport.find_by(label: "Hiking") || create(:sport, slug: "test_hiking", label: "Hiking")

    expect(view.sport).to eq(sport)
  end

  it "falls back to a neutral sport for an unknown label" do
    unknown = create(
      :remote_note,
      sport_label: "Extreme curling",
      representation: representation.merge("sport_label" => "Extreme curling")
    )

    fallback = described_class.new(unknown).sport

    expect(fallback.slug).to eq("remote")
    expect(fallback.colour_group).to eq("other")
    expect(fallback.icon).to eq("sports/icons/families/other")
    expect(fallback.translated_name).to eq("Extreme curling")
    expect(fallback.pace_speed_display).to eq("speed")
    expect(fallback.pace_basis_metres).to be_nil
    expect(fallback).not_to be_pace_basis
    expect(fallback).not_to be_power_led
    expect(fallback.cadence_unit).to be_nil
  end

  it "recognizes a power-led virtual sport from the shared catalog" do
    sport = catalog_sport("cycling_virtual")
    virtual = create(
      :remote_note,
      sport_label: sport.label,
      representation: representation.merge(
        "sport_label" => sport.label,
        "metrics" => { "distance" => 20_000, "average_power" => 210 }
      )
    )

    view = described_class.new(virtual)

    expect(view.sport).to eq(sport)
    expect(view.sport).to be_power_led
    expect(view.metric_visible?(:average_power)).to be(true)
  end

  it "falls back to the title from the sport label and then a generic label" do
    from_label = create(:remote_note, title: nil, sport_label: "Hiking")
    expect(described_class.new(from_label).title).to eq("Hiking")

    generic = create(:remote_note, title: nil, sport_label: nil)
    expect(described_class.new(generic).title).to eq(I18n.t("remote_notes.untitled"))
  end

  it "requires a cached blob for media visibility and reports pending states" do
    expect(view.route_image_visible?).to be(false)
    expect(view.gpx_visible?).to be(false)

    attachment = create(:remote_note_attachment, remote_note: note, kind: "gpx", status: "pending")
    expect(described_class.new(note.reload).media_pending?).to be(true)

    attachment.update!(
      status: "cached",
      blob: ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new("data"), filename: "track.gpx", content_type: "application/xml+gpx"
      )
    )

    reloaded = described_class.new(note.reload)
    expect(reloaded.gpx_visible?).to be(true)
    expect(reloaded.media_pending?).to be(false)
  end

  it "reports an unavailable media state" do
    create(:remote_note_attachment, remote_note: note, kind: "gpx", status: "unavailable")

    expect(described_class.new(note.reload).media_unavailable?).to be(true)
    expect(described_class.new(note.reload).media_cached?).to be(false)
  end
end
