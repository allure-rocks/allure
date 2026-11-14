# frozen_string_literal: true

require "rails_helper"

RSpec.describe TrackSegment do
  it "orders a workout's segments by explicit position" do
    workout = create(:workout)
    later = create(:track_segment, workout:, position: 1)
    earlier = create(:track_segment, workout:, position: 0)

    expect(workout.track_segments.reload).to eq([ earlier, later ])
  end

  it "requires positions to be unique within a workout" do
    workout = create(:workout)
    create(:track_segment, workout:, position: 0)
    expect(build(:track_segment, workout:, position: 0)).not_to be_valid
  end

  it "round-trips a LineString geography without joining another segment" do
    segment = create(:track_segment).reload

    expect(segment.geom).to be_a(RGeo::Feature::LineString)
    expect(segment.geom.srid).to eq(4326)
    expect(segment.geom.points.map { [ it.x.round(4), it.y.round(4) ] })
      .to eq([ [ 6.4074, 45.0710 ], [ 6.4092, 45.0728 ] ])
  end

  it "persists the compact point array exactly" do
    segment = create(:track_segment).reload
    expect(segment.points.length).to eq(2)
    expect(segment.points.first).to eq(
      "t" => 0, "d" => 0.0, "lat" => 45.071, "lon" => 6.4074, "ele" => 100.0
    )
  end

  it "rejects point-count drift in the database" do
    segment = create(:track_segment)
    expect { segment.update_column(:points_count, 3) }
      .to raise_error(ActiveRecord::StatementInvalid, /track_segments_points/)
  end

  it "enforces position uniqueness in the database" do
    workout = create(:workout)
    create(:track_segment, workout:, position: 0)
    segment = create(:track_segment, workout:, position: 1)

    expect { segment.update_column(:position, 0) }
      .to raise_error(ActiveRecord::RecordNotUnique, /index_track_segments_on_workout_id_and_position/)
  end

  it "has a GiST index for track queries" do
    index = described_class.connection.indexes(:track_segments).find { it.columns == [ "geom" ] }
    expect(index.using).to eq(:gist)
  end

  it "is deleted with its workout" do
    segment = create(:track_segment)
    expect { segment.workout.destroy! }.to change(described_class, :count).by(-1)
  end
end
