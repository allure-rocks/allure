# frozen_string_literal: true

require "rails_helper"

RSpec.describe Segments::RemoteImporter do
  let(:user) { create(:user) }
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
  let(:representation) do
    {
      "name" => "Remote climb",
      "description" => "A remote climb",
      "sport_slug" => "cycling",
      "kind" => "segment",
      "distance" => 2500.0,
      "ascent" => 180.0,
      "descent" => 12.0,
      "average_grade" => 7.2,
      "match_tolerance" => 25,
      "track" => track
    }
  end
  let(:remote_segment) { create(:remote_segment, representation:) }

  before do
    sport
    create(:remote_segment_attachment, remote_segment:, kind: "gpx", status: "cached")
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
  end

  after { ActiveJob::Base.queue_adapter.enqueued_jobs.clear }

  def import
    described_class.new(user:, remote_segment:).call!
  end

  def set_representation(value)
    RemoteSegment.where(id: remote_segment.id).update_all(representation: value)
    remote_segment.reload
  end

  it "creates a private, owner-only copy with re-derived geometry" do
    result = import
    segment = result.segment

    expect(segment).to have_attributes(
      user:,
      remote_segment:,
      kind: "segment",
      visibility: "private",
      source_workout: nil,
      match_tolerance_meters: 25,
      sport:
    )
    expect(segment.geom.num_points).to eq(2)
    expect(segment.signature.length).to eq(64)
    expect(segment.bounds.length).to eq(4)
    expect(segment.distance).to be > 0
    expect(segment.ascent.to_f).to eq(180.0)
    expect(result.warnings).to be_empty
    expect(Segments::BackfillSegmentJob).to have_been_enqueued.with(segment)
  end

  it "is idempotent for the same user and remote course" do
    first = import.segment

    expect { import }.not_to change(Segment, :count)
    expect(import.segment).to eq(first)
  end

  it "imports an unknown sport slug as all-sports with a warning" do
    set_representation(representation.merge("sport_slug" => "unicycle"))

    result = import

    expect(result.segment.sport).to be_nil
    expect(result.warnings.join).to include("unicycle")
  end

  it "imports an absent sport as all-sports without a warning" do
    set_representation(representation.except("sport_slug"))

    result = import

    expect(result.segment.sport).to be_nil
    expect(result.warnings).to be_empty
  end

  it "rejects a multi-feature track instead of flattening it" do
    feature = track["features"].first
    set_representation(
      representation.merge(
        "track" => { "type" => "FeatureCollection", "features" => [ feature, feature ] }
      )
    )

    expect { import }.to raise_error(described_class::ImportError, I18n.t("segments.remote_copy.errors.no_track"))
  end

  it "rejects a course whose media is not cached yet" do
    remote_segment.attachments.update_all(status: "pending")

    expect { import }
      .to raise_error(described_class::ImportError, I18n.t("segments.remote_copy.errors.pending_media"))
  end

  it "rejects an inactive or purged course" do
    remote_segment.mark_deleted!
    expect { import }
      .to raise_error(described_class::ImportError, I18n.t("segments.remote_copy.errors.unavailable"))

    active = create(:remote_segment, representation:)
    create(:remote_segment_attachment, remote_segment: active, kind: "gpx", status: "cached")
    active.redact_location!
    expect { described_class.new(user:, remote_segment: active).call! }
      .to raise_error(described_class::ImportError, I18n.t("segments.remote_copy.errors.purged"))
  end

  it "keeps the local copy after the remote course is deleted" do
    segment = import.segment

    remote_segment.mark_deleted!
    remote_segment.attachments.update_all(status: "purged", blob_id: nil)

    expect(segment.reload).to be_persisted
    expect(segment.remote_segment).to eq(remote_segment)
  end
end
