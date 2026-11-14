# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Segments::Matcher do
  let(:factory) { RGeo::Geographic.spherical_factory(srid: 4326) }
  let(:coordinates) { [ [ 6.4000, 45.0000 ], [ 6.4000, 45.0010 ], [ 6.4000, 45.0020 ] ] }
  let(:segment_geometry) { factory.line_string(coordinates.map { |longitude, latitude| factory.point(longitude, latitude) }) }
  let(:segment_distance) do
    coordinates.each_cons(2).sum do |first, second|
      Allure::Gpx::Geo.horizontal_distance(first.last, first.first, second.last, second.first)
    end
  end
  let(:segment) do
    instance_double(
      Segment,
      kind: "segment",
      geom: segment_geometry,
      distance: segment_distance,
      signature: Array.new(64, 0.0),
      match_tolerance_meters: 10
    )
  end
  let(:started_at) { Time.utc(2026, 8, 28, 8, 0, 0) }

  it "returns repeated traversals in occurrence order with derived metrics" do
    points = points_for(coordinates * 3)

    efforts = described_class.new(segment:, points:).call

    expect(efforts.length).to eq(3)
    expect(efforts.map(&:occurrence_index)).to eq([ 0, 1, 2 ])
    expect(efforts.map(&:start_point_index)).to eq([ 0, 3, 6 ])
    expect(efforts.map(&:end_point_index)).to eq([ 2, 5, 8 ])
    expect(efforts.map(&:elapsed_time)).to eq([ 120, 120, 120 ])
    expect(efforts).to all(have_attributes(moving_time: 120, deviation_meters: 0.0))
    expect(efforts.first).to have_attributes(
      distance: be_within(0.1).of(segment_distance),
      ascent: 20.0,
      descent: 0.0,
      average_heart_rate: 140,
      max_heart_rate: 140,
      average_cadence: 80,
      average_power: 200,
      max_power: 200
    )
  end

  it "rejects a traversal that crosses a recording-segment boundary" do
    points = points_for(coordinates, segment_indexes: [ 0, 0, 1 ])

    expect(described_class.new(segment:, points:).call).to be_empty
  end

  it "rejects a reversed traversal" do
    expect(described_class.new(segment:, points: points_for(coordinates.reverse)).call).to be_empty
  end

  it "prefers the exit closest to the canonical end when several are valid" do
    course = [ [ 6.4000, 45.0 ], [ 6.4030, 45.0 ] ]
    # Approaches the end, moves away past it, then returns much closer. Both the
    # first approach and the final point are valid exits.
    overshooting = [ 6.4000, 6.4010, 6.4020, 6.4028, 6.4032, 6.4029, 6.40301 ].map { |lon| [ lon, 45.0 ] }

    segment = segment_for(course, match_tolerance_meters: 25)
    efforts = described_class.new(segment:, points: points_for(overshooting)).call

    expect(efforts.length).to eq(1)
    expect(efforts.first.end_point_index).to eq(6)
  end

  it "rejects endpoints beyond the shape tolerance, which Fréchet would reject anyway" do
    course = [ [ 6.4000, 45.0 ], [ 6.4030, 45.0 ] ]
    # The same shape, translated roughly 44 m north: every endpoint sits outside
    # the 25 m tolerance, so no traversal can be bracketed.
    offset = [ 6.4000, 6.4010, 6.4020, 6.4030 ].map { |lon| [ lon, 45.0004 ] }
    segment = segment_for(course, match_tolerance_meters: 25)

    expect(described_class.new(segment:, points: points_for(offset)).call).to be_empty
  end

  it "finds three ordered traversals in the GPX fixture" do
    course = [ [ 6.40000, 45.00000 ], [ 6.40180, 45.00000 ], [ 6.40180, 45.00055 ],
               [ 6.40000, 45.00055 ], [ 6.40000, 45.00000 ] ]
    points = points_from_fixture("three_laps")
    fixture_segment = segment_for(course)

    efforts = described_class.new(segment: fixture_segment, points:).call

    expect(efforts.map(&:occurrence_index)).to eq([ 0, 1, 2 ])
  end

  it "does not match a segment traversed across a GPX recording gap" do
    course = [ [ 6.40000, 45.00000 ], [ 6.40100, 45.00000 ], [ 6.40100, 45.00100 ] ]
    points = points_from_fixture("gap_inside_segment")

    expect(described_class.new(segment: segment_for(course), points:).call).to be_empty
  end

  it "keeps the same verdict for loop endpoint pairs without a quadratic product" do
    course = [ [ 6.4, 45.0 ], [ 6.403, 45.0 ], [ 6.403, 45.002 ], [ 6.4, 45.002 ], [ 6.4, 45.0 ] ]
    points = points_for(course + Array.new(99) { course.drop(1) }.flatten(1))
    loop_matcher = described_class.new(segment: segment_for(course, kind: "loop"), points:)
    allow(loop_matcher).to receive(:match).and_call_original

    efforts = loop_matcher.call

    expect(efforts.length).to eq(100)
    expect(loop_matcher).to have_received(:match).at_most(101).times
    expect(efforts).to eq(described_class.new(segment: segment_for(course), points:).call)
  end

  it "summarizes the same accepted boundaries and coverage without calculating sensor metrics" do
    points = points_for(coordinates * 3)
    matcher = described_class.new(segment:, points:)
    full = matcher.call
    allow(Allure::Gpx::Elevation).to receive(:ascent_and_descent).and_call_original

    summaries = matcher.call(summary_only: true)

    expect(summaries.map(&:to_h)).to eq(full.map { |effort| effort.to_h.slice(*Allure::Segments::EffortMetrics::Summary.members) })
    expect(Allure::Gpx::Elevation).not_to have_received(:ascent_and_descent)
  end

  it "refuses zero-duration summaries just as it refuses full efforts" do
    points = points_for(coordinates).map { |point| point.with(time: started_at) }
    matcher = described_class.new(segment:, points:)

    expect(matcher.call(summary_only: true)).to be_empty
    expect(matcher.call).to be_empty
  end

  describe "a route (kind: route), matched end to end" do
    let(:course) do
      [ [ 6.4000, 45.0000 ], [ 6.4030, 45.0000 ], [ 6.4030, 45.0011 ] ]
    end
    let(:route) { segment_for(course, kind: "route") }

    it "matches a complete repeat of the whole track once" do
      efforts = described_class.new(segment: route, points: points_for(course)).call

      expect(efforts.length).to eq(1)
      expect(efforts.first).to have_attributes(
        occurrence_index: 0,
        start_point_index: 0,
        end_point_index: 2
      )
    end

    it "accepts a route that spans a recording-segment boundary" do
      points = points_for(course, segment_indexes: [ 0, 1, 1 ])

      expect(described_class.new(segment: route, points:).call.length).to eq(1)
    end

    it "rejects a partial traversal outside the ±10 % length window" do
      expect(described_class.new(segment: route, points: points_for(course[0..1])).call).to be_empty
    end

    it "rejects a route whose endpoints sit beyond the tolerance" do
      offset = course.map { |longitude, latitude| [ longitude, latitude + 0.0004 ] }

      expect(described_class.new(segment: route, points: points_for(offset)).call).to be_empty
    end

    it "rejects a reversed complete track" do
      expect(described_class.new(segment: route, points: points_for(course.reverse)).call).to be_empty
    end

    it "matches a complete GPX repeat of the route end to end" do
      points = points_from_fixture("route_repeat")
      route = segment_for(points.map(&:coordinate), kind: "route", match_tolerance_meters: 25)

      expect(described_class.new(segment: route, points:).call.length).to eq(1)
    end
  end

  private

  def points_for(sequence, segment_indexes: nil)
    distance = 0.0
    sequence.each_with_index.map do |coordinate, index|
      if index.positive?
        distance += Allure::Gpx::Geo.horizontal_distance(
          sequence[index - 1].last,
          sequence[index - 1].first,
          coordinate.last,
          coordinate.first
        )
      end

      Allure::Segments::Point.new(
        index: index,
        segment_index: segment_indexes&.fetch(index, 0) || 0,
        segment_point_index: index,
        time: started_at + (index * 60),
        elapsed_time: index * 60,
        distance: distance,
        longitude: coordinate.first,
        latitude: coordinate.last,
        elevation: 100.0 + (index * 10),
        speed: 2.0,
        heart_rate: 140,
        cadence: 80,
        power: 200
      )
    end
  end

  def points_from_fixture(name)
    metrics = analyze_gpx_fixture(name, stopped_speed_threshold_km_h: 0.5, records_elevation: false)
    Allure::Segments::PointStream.new(
      segments: metrics.segments,
      workout_started_at: metrics.started_at
    ).call
  end

  def segment_for(course, match_tolerance_meters: 10, kind: "segment")
    geometry = factory.line_string(course.map { |longitude, latitude| factory.point(longitude, latitude) })
    distance = course.each_cons(2).sum do |first, second|
      Allure::Gpx::Geo.horizontal_distance(first.last, first.first, second.last, second.first)
    end

    instance_double(
      Segment,
      kind: kind,
      geom: geometry,
      distance: distance,
      signature: Allure::Geometry::ShapeSignature.compute(course),
      match_tolerance_meters: match_tolerance_meters
    )
  end
end
