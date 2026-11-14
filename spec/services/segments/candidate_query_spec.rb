# frozen_string_literal: true

require "rails_helper"

RSpec.describe Segments::CandidateQuery do
  before do
    allow(Segments::BackfillSegmentJob).to receive(:perform_later)
  end

  it "returns only active owner segments that are spatial candidates for a workout" do
    user = create(:user)
    sport = create(:sport)
    workout = create(:workout, user:, sport:)
    create(:track_segment, workout:)
    matching = create(:segment, user:, sport:)
    inactive = create(:segment, user:, sport:, active: false)
    other_user_segment = create(:segment, sport:)

    expect(described_class.for_workout(workout)).to contain_exactly(matching)
    expect(described_class.for_workout(workout)).not_to include(inactive, other_user_segment)
  end

  it "returns only active owner routes that are spatial candidates for a workout" do
    user = create(:user)
    sport = create(:sport)
    workout = create(:workout, user:, sport:)
    create(:track_segment, workout:)
    matching_route = create(:segment, :route, user:, sport:)
    plain_segment = create(:segment, user:, sport:)
    inactive_route = create(:segment, :route, user:, sport:, active: false)
    other_route = create(:segment, :route, sport:)

    expect(described_class.for_route_workout(workout)).to contain_exactly(matching_route)
    expect(described_class.for_route_workout(workout)).not_to include(plain_segment, inactive_route, other_route)
  end

  it "widens the route endpoint prefilter for a caller that judges it at a larger tolerance" do
    user = create(:user)
    sport = create(:sport)
    workout = create(:workout, user:, sport:)
    create(:track_segment, workout:)
    factory = RGeo::Geographic.spherical_factory(srid: 4326)
    offset = 60 / 111_320.0
    route = create(
      :segment, :route, user:, sport:, match_tolerance_meters: 25,
      start_point: factory.point(6.4074, 45.0710 + offset),
      end_point: factory.point(6.4092, 45.0728 + offset)
    )

    expect(described_class.for_route_workout(workout)).not_to include(route)
    expect(described_class.for_route_workout(workout, minimum_tolerance: 100)).to include(route)
  end

  it "returns matching owner workouts for backfill" do
    user = create(:user)
    sport = create(:sport)
    workout = create(:workout, user:, sport:)
    create(:track_segment, workout:)
    segment = create(:segment, user:, sport:)

    expect(described_class.for_segment(segment)).to contain_exactly(workout)
  end

  it "prefilters known loops by owner, activity, distance tolerance and endpoints, but not sport" do
    workout = create(:workout, distance: 250)
    create(:track_segment, workout:)
    matching = create(:segment, :loop, user: workout.user, distance: 300)
    create(:segment, :loop, user: workout.user, active: false)
    create(:segment, :loop, user: workout.user, distance: 500)
    create(:segment, :loop)
    create(:segment, user: workout.user)

    expect(matching.sport).not_to eq(workout.sport)
    expect(described_class.for_loop_workout(workout)).to contain_exactly(matching)
  end

  it "does not offer known loops when their endpoints are far from the recording" do
    workout = create(:workout)
    create(:track_segment, workout:)
    factory = RGeo::Geographic.spherical_factory(srid: 4326)
    create(:segment, :loop, user: workout.user, start_point: factory.point(1, 1))

    expect(described_class.for_loop_workout(workout)).to be_empty
  end

  it "backfills owner workouts inside a route's ±10 % length window" do
    user = create(:user)
    sport = create(:sport)
    workout = create(:workout, user:, sport:, distance: 250.0)
    create(:track_segment, workout:)
    route = create(:segment, :route, user:, sport:, distance: 250.0)

    expect(described_class.for_segment(route)).to contain_exactly(workout)
  end

  it "does not backfill a workout outside a route's length window" do
    user = create(:user)
    sport = create(:sport)
    workout = create(:workout, user:, sport:, distance: 400.0)
    create(:track_segment, workout:)
    route = create(:segment, :route, user:, sport:, distance: 250.0)

    expect(described_class.for_segment(route)).not_to include(workout)
  end

  it "does not backfill an inactive segment" do
    user = create(:user)
    sport = create(:sport)
    workout = create(:workout, user:, sport:)
    create(:track_segment, workout:)
    segment = create(:segment, user:, sport:, active: false)

    expect(described_class.for_segment(segment)).to be_empty
  end

  it "allows a sport-agnostic segment to match any workout sport" do
    user = create(:user)
    workout = create(:workout, user:)
    create(:track_segment, workout:)
    segment = create(:segment, user:, sport: nil)

    expect(described_class.for_segment(segment)).to contain_exactly(workout)
  end

  it "includes another user's shared segment for a workout but not their private one" do
    user = create(:user)
    other = create(:user)
    sport = create(:sport)
    workout = create(:workout, user:, sport:)
    create(:track_segment, workout:)
    shared = create(:segment, user: other, sport:, visibility: "public")
    private_segment = create(:segment, user: other, sport:)

    expect(described_class.for_workout(workout)).to include(shared)
    expect(described_class.for_workout(workout)).not_to include(private_segment)
  end

  it "backfills other users' workouts for a shared segment" do
    owner = create(:user)
    other = create(:user)
    sport = create(:sport)
    own_workout = create(:workout, user: owner, sport:)
    create(:track_segment, workout: own_workout)
    other_workout = create(:workout, user: other, sport:)
    create(:track_segment, workout: other_workout)
    segment = create(:segment, user: owner, sport:, visibility: "public")

    expect(described_class.for_segment(segment)).to contain_exactly(own_workout, other_workout)
  end

  it "matches an all-sports segment against workouts of several sports" do
    user = create(:user)
    cyclist = create(:sport)
    runner = create(:sport)
    segment = create(:segment, user:, sport: nil)
    ride = create(:workout, user:, sport: cyclist)
    run = create(:workout, user:, sport: runner)
    create(:track_segment, workout: ride)
    create(:track_segment, workout: run)

    expect(described_class.for_workout(ride)).to include(segment)
    expect(described_class.for_workout(run)).to include(segment)
    expect(described_class.for_segment(segment)).to contain_exactly(ride, run)
  end

  it "keeps a sported segment out of another sport's candidate set" do
    user = create(:user)
    cyclist = create(:sport)
    runner = create(:sport)
    segment = create(:segment, user:, sport: cyclist)
    run = create(:workout, user:, sport: runner)
    create(:track_segment, workout: run)

    expect(described_class.for_workout(run)).not_to include(segment)
    expect(described_class.for_segment(segment)).to be_empty
  end
end
