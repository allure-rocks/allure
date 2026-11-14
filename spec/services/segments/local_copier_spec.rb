# frozen_string_literal: true

require "rails_helper"

RSpec.describe Segments::LocalCopier do
  include ActiveJob::TestHelper

  let(:owner) { create(:user) }
  let(:copier) { create(:user) }
  let(:sport) { create(:sport) }
  let(:factory) { RGeo::Geographic.spherical_factory(srid: 4326) }
  let(:coordinates) { [ [ 6.4074, 45.0710 ], [ 6.4084, 45.0712 ], [ 6.4092, 45.0728 ] ] }
  let(:profile) do
    [
      { "d" => 0.0, "ele" => 100.0 },
      { "d" => 100.0, "ele" => 120.0 },
      { "d" => 250.0, "ele" => 90.0 }
    ]
  end
  let(:source) do
    create(
      :segment,
      user: owner,
      sport:,
      geom: factory.line_string(coordinates.map { |longitude, latitude| factory.point(longitude, latitude) }),
      start_point: factory.point(*coordinates.first),
      end_point: factory.point(*coordinates.last),
      bounds: [ 45.0710, 6.4074, 45.0728, 6.4092 ],
      distance: 250.0,
      ascent: 20.0,
      descent: 5.0,
      min_elevation: 90.0,
      max_elevation: 120.0,
      average_grade: 8.0,
      elevation_profile: profile,
      signature: Allure::Geometry::ShapeSignature.compute(coordinates)
    )
  end

  describe "forward copy" do
    it "copies the course into a private segment without a source" do
      result = described_class.new(user: copier, segment: source).call!
      copy = result.segment

      expect(copy).to be_persisted
      expect(copy).to have_attributes(
        user: copier,
        name: source.name,
        description: source.description,
        kind: "segment",
        sport:,
        visibility: "private",
        active: true,
        match_tolerance_meters: source.match_tolerance_meters,
        source_workout: nil,
        source_start_index: nil,
        source_end_index: nil,
        remote_segment: nil,
        distance: source.distance,
        ascent: source.ascent,
        descent: source.descent,
        min_elevation: source.min_elevation,
        max_elevation: source.max_elevation,
        average_grade: source.average_grade,
        elevation_profile: profile
      )
      expect(copy.geom.points.map { |point| [ point.x, point.y ] }).to eq(coordinates)
      expect([ copy.start_point.x, copy.start_point.y ]).to eq(coordinates.first)
      expect([ copy.end_point.x, copy.end_point.y ]).to eq(coordinates.last)
      expect(copy.bounds).to eq(source.bounds)
      expect(copy.signature).to eq(source.signature)
    end

    it "enqueues the copier's own workout backfill" do
      source
      ActiveJob::Base.queue_adapter.enqueued_jobs.clear

      expect { described_class.new(user: copier, segment: source).call! }
        .to have_enqueued_job(Segments::BackfillSegmentJob).exactly(:once)
    end
  end

  describe "reversed copy" do
    it "reverses the geometry, swaps the elevation aggregates and mirrors the profile" do
      result = described_class.new(user: copier, segment: source, reversed: true).call!
      copy = result.segment

      expect(copy.geom.points.map { |point| [ point.x, point.y ] }).to eq(coordinates.reverse)
      expect([ copy.start_point.x, copy.start_point.y ]).to eq(coordinates.last)
      expect([ copy.end_point.x, copy.end_point.y ]).to eq(coordinates.first)
      expect(copy.bounds).to eq(source.bounds)
      expect(copy.distance).to eq(source.distance)
      expect(copy.ascent).to eq(source.descent)
      expect(copy.descent).to eq(source.ascent)
      expect(copy.min_elevation).to eq(source.min_elevation)
      expect(copy.max_elevation).to eq(source.max_elevation)
      expect(copy.average_grade).to be_within(0.001).of(-8.0)
      expect(copy.signature).to eq(Allure::Geometry::ShapeSignature.compute(coordinates.reverse))
      expect(copy.signature).not_to eq(source.signature)
      expect(copy.elevation_profile).to eq(
        [
          { "d" => 0.0, "ele" => 90.0 },
          { "d" => 150.0, "ele" => 120.0 },
          { "d" => 250.0, "ele" => 100.0 }
        ]
      )
      expect(copy.name).to eq(I18n.t("segments.copy.reversed_name", name: source.name))
    end

    it "keeps a course without usable elevation without one" do
      bare = create(:segment, user: owner, sport:, elevation_profile: [])

      copy = described_class.new(user: copier, segment: bare, reversed: true).call!.segment

      expect(copy.elevation_profile).to eq([])
    end
  end

  describe "provenance and kind" do
    it "preserves the source kind, so a reversed route stays a route" do
      workout = create(:workout, user: owner, sport:)
      route = create(:segment, :route, user: owner, sport:, source_workout: workout)

      copy = described_class.new(user: owner, segment: route, reversed: true).call!.segment

      expect(copy).to have_attributes(kind: "route", visibility: "private", source_workout: workout)
    end

    it "keeps the source activity link for the owner only" do
      workout = create(:workout, user: owner, sport:)
      own = create(:segment, user: owner, sport:, source_workout: workout)

      own_copy = described_class.new(user: owner, segment: own, reversed: true).call!.segment
      other_copy = described_class.new(user: copier, segment: own, reversed: false).call!.segment

      expect(own_copy.source_workout).to eq(workout)
      expect(other_copy.source_workout).to be_nil
    end
  end
end
