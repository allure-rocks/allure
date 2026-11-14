# frozen_string_literal: true

require "rails_helper"

RSpec.describe Segments::LoopReuse do
  CIRCUIT = [
    [ 0.0, 0.0 ],
    [ 0.01, 0.0 ],
    [ 0.01, 0.005 ],
    [ 0.0, 0.005 ],
    [ 0.0, 0.0 ]
  ].freeze

  def loop_segment(user:, coordinates: CIRCUIT, distance: 1_000.0, sport: nil, renamed_at: nil)
    factory = RGeo::Geographic.spherical_factory(srid: 4326)
    latitudes = coordinates.map(&:last)
    longitudes = coordinates.map(&:first)

    create(
      :segment,
      :loop,
      user:,
      sport: sport || create(:sport),
      geom: factory.line_string(coordinates.map { |longitude, latitude| factory.point(longitude, latitude) }),
      start_point: factory.point(*coordinates.first),
      end_point: factory.point(*coordinates.last),
      bounds: [ latitudes.min, longitudes.min, latitudes.max, longitudes.max ],
      distance:,
      renamed_at:
    )
  end

  def candidate(coordinates: CIRCUIT, travelled: 1_000.0)
    Allure::Geometry::LoopDetector::Candidate.new(
      start_index: 0,
      end_index: coordinates.length - 1,
      travelled_distance_meters: travelled,
      closure_distance_meters: 5.0,
      coordinates:
    )
  end

  it "elects the oldest similar loop of the owner" do
    workout = create(:workout)
    older = loop_segment(user: workout.user)
    loop_segment(user: workout.user)

    expect(described_class.new(workout:, candidate: candidate).call).to eq(older)
  end

  it "elects an owner-renamed loop over an older auto-named one" do
    workout = create(:workout)
    loop_segment(user: workout.user)
    renamed = loop_segment(user: workout.user, renamed_at: Time.current)

    expect(described_class.new(workout:, candidate: candidate).call).to eq(renamed)
  end

  it "ignores a loop whose length is outside the matcher window" do
    workout = create(:workout)
    loop_segment(user: workout.user, distance: 5_000.0)

    expect(described_class.new(workout:, candidate: candidate(travelled: 1_000.0)).call).to be_nil
  end

  it "ignores a loop whose geometry diverges" do
    workout = create(:workout)
    loop_segment(user: workout.user, coordinates: CIRCUIT.map { |longitude, latitude| [ longitude + 0.5, latitude ] })

    expect(described_class.new(workout:, candidate: candidate).call).to be_nil
  end

  it "ignores another owner's loop" do
    workout = create(:workout)
    loop_segment(user: create(:user))

    expect(described_class.new(workout:, candidate: candidate).call).to be_nil
  end

  it "reuses across sports" do
    workout = create(:workout)
    stored = loop_segment(user: workout.user, sport: create(:sport))

    expect(described_class.new(workout:, candidate: candidate).call).to eq(stored)
  end
end
