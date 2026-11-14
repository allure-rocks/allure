# frozen_string_literal: true

require "rails_helper"

RSpec.describe Segments::Creator do
  let(:user) { create(:user) }
  let(:sport) { create(:sport) }
  let(:workout) { create(:workout, user:, sport:, points_count: 3, distance: 200.0) }

  before do
    create(
      :track_segment,
      workout:,
      position: 0,
      distance: 200.0,
      points: [
        { "t" => 0, "d" => 0.0, "lat" => 45.0710, "lon" => 6.4074, "ele" => 100.0 },
        { "t" => 30, "d" => 100.0, "lat" => 45.0710, "lon" => 6.4084, "ele" => 105.0 },
        { "t" => 60, "d" => 200.0, "lat" => 45.0710, "lon" => 6.4094, "ele" => 110.0 }
      ]
    )
  end

  it "reconstructs a private segment from the owned workout points" do
    segment = described_class.new(
      user:,
      workout:,
      name: "Quai test",
      description: "A selected portion",
      start_index: 0,
      end_index: 2,
      match_tolerance_meters: 30
    ).call

    expect(segment).to be_persisted
    expect(segment).to have_attributes(
      name: "Quai test",
      description: "A selected portion",
      kind: "segment",
      visibility: "private",
      source_workout: workout,
      source_start_index: 0,
      source_end_index: 2,
      distance: be_within(0.1).of(200.0),
      ascent: be > 0,
      matcher_version: Allure::Segments::Matcher::VERSION,
      match_tolerance_meters: 30
    )
    expect(segment.geom.num_points).to eq(3)
    expect(segment.signature.length).to eq(64)
  end

  it "stores the frozen elevation profile of the selection" do
    segment = described_class.new(
      user:,
      workout:,
      name: "Profilé",
      start_index: 0,
      end_index: 2
    ).call

    expect(segment.elevation_profile).to eq(
      [
        { "d" => 0.0, "ele" => 100.0 },
        { "d" => 100.0, "ele" => 105.0 },
        { "d" => 200.0, "ele" => 110.0 }
      ]
    )
  end

  it "inherits the source workout sport when no sport is given" do
    segment = described_class.new(
      user:,
      workout:,
      name: "Hérité",
      start_index: 0,
      end_index: 2
    ).call

    expect(segment).to be_persisted
    expect(segment.sport).to eq(sport)
  end

  it "creates an all-sports segment when sport is nil" do
    segment = described_class.new(
      user:,
      workout:,
      name: "Tous sports",
      start_index: 0,
      end_index: 2,
      sport: nil
    ).call

    expect(segment).to be_persisted
    expect(segment.sport).to be_nil
  end

  it "rejects a selection that crosses a recording boundary" do
    second = create(:track_segment, workout:, position: 1, started_at: workout.started_at + 120.seconds)

    segment = described_class.new(
      user:,
      workout:,
      name: "Invalid gap",
      start_index: 1,
      end_index: 3
    ).call

    expect(segment).not_to be_persisted
    expect(segment.errors[:base]).to include(
      I18n.t("activerecord.errors.models.segment.attributes.base.invalid_selection")
    )
    expect(second).to be_persisted
  end

  it "rejects a workout owned by another user" do
    other = create(:user)
    other_workout = create(:workout, user: other, sport:)
    create(:track_segment, workout: other_workout, position: 0)

    segment = described_class.new(
      user:,
      workout: other_workout,
      name: "Not mine",
      start_index: 0,
      end_index: 1
    ).call

    expect(segment).not_to be_persisted
  end

  it "applies the visibility chosen at creation" do
    segment = described_class.new(
      user:,
      workout:,
      name: "Partagé",
      start_index: 0,
      end_index: 2,
      visibility: "followers_only"
    ).call

    expect(segment).to be_persisted
    expect(segment.visibility).to eq("followers_only")
  end

  it "records the privacy-zone acknowledgment when one is given" do
    segment = described_class.new(
      user:,
      workout:,
      name: "Zoned",
      start_index: 0,
      end_index: 2,
      visibility: "public",
      zone_acknowledged: true
    ).call

    expect(segment).to be_persisted
    expect(segment.privacy_zone_acknowledged_at).to be_present
  end

  it "rejects an unknown visibility instead of silently keeping the private default" do
    segment = described_class.new(
      user:,
      workout:,
      name: "Bogus",
      start_index: 0,
      end_index: 2,
      visibility: "bogus"
    ).call

    expect(segment).not_to be_persisted
    expect(segment.errors[:visibility]).to be_present
  end

  it "keeps a route private even when a visibility is supplied" do
    segment = described_class.new(
      user:,
      workout:,
      kind: "route",
      name: "Whole track",
      visibility: "public"
    ).call

    expect(segment).to be_persisted
    expect(segment.visibility).to eq("private")
  end

  it "saves a complete workout as a whole-track route" do
    segment = described_class.new(
      user:,
      workout:,
      kind: "route",
      name: "Whole track"
    ).call

    expect(segment).to be_persisted
    expect(segment).to have_attributes(
      kind: "route",
      name: "Whole track",
      visibility: "private",
      source_workout: workout,
      source_start_index: 0,
      source_end_index: 2
    )
    expect(segment.geom.num_points).to eq(3)
  end

  it "defaults a route to the route tolerance" do
    segment = described_class.new(user:, workout:, kind: "route", name: "Whole track").call

    expect(segment.match_tolerance_meters).to eq(described_class::ROUTE_MATCH_TOLERANCE_METERS)
  end

  it "keeps the segment default for a segment" do
    segment = described_class.new(user:, workout:, name: "Climb", start_index: 0, end_index: 2).call

    expect(segment.match_tolerance_meters).to eq(described_class::DEFAULT_MATCH_TOLERANCE_METERS)
  end

  it "keeps an explicit route tolerance" do
    segment = described_class.new(
      user:, workout:, kind: "route", name: "Whole track", match_tolerance_meters: 25
    ).call

    expect(segment.match_tolerance_meters).to eq(25)
  end

  it "saves a route across a recording boundary, which would reject a partial segment" do
    create(:track_segment, workout:, position: 1, started_at: workout.started_at + 120.seconds)

    segment = described_class.new(
      user:,
      workout:,
      kind: "route",
      name: "Whole loop"
    ).call

    expect(segment).to be_persisted
    expect(segment).to have_attributes(kind: "route", source_start_index: 0, source_end_index: 4)
  end
end
