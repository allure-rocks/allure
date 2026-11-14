# frozen_string_literal: true

require "rails_helper"

RSpec.describe Segments::TerrainElevation do
  let(:user) { create(:user, elevation_enrichment_enabled: false) }
  let(:client) { instance_double(Allure::Elevation::OpenTopoData) }
  let(:config_class) do
    Data.define(:base_url, :dataset, :sample_metres, :requests_per_second, :max_requests_per_workout, :configured) do
      def configured? = configured
    end
  end
  let(:config) do
    config_class.new(base_url: "https://elevation.test", dataset: "mapzen", sample_metres: 50.0,
                     requests_per_second: 100.0, max_requests_per_workout: 10, configured: true)
  end
  let(:unconfigured) { config.with(configured: false) }

  # About 1 km climbing west to east; the terrain answers a 50 m descent.
  def course(**attributes)
    factory = RGeo::Geographic.spherical_factory(srid: 4326)
    line = factory.line_string([ factory.point(6.0, 45.0), factory.point(6.0127, 45.0) ])
    create(:segment, user:, geom: line, distance: 1_000.0, ascent: 3.0, descent: 1.0,
                     average_grade: 0.2, visibility: "private", **attributes)
  end

  before do
    allow(client).to receive(:elevations) do |locations|
      locations.map { |_latitude, longitude| 500.0 - ((longitude - 6.0) / 0.0127 * 50.0) }
    end
  end

  def apply(segment, config: self.config)
    described_class.new(segment:, config:, client:, sleeper: ->(_) { }).call
    segment.reload
  end

  describe ".eligible?" do
    it "takes a public course without consent, a private one only with it" do
      expect(described_class.eligible?(course(visibility: "public"), config:)).to be(true)
      expect(described_class.eligible?(course, config:)).to be(false)

      user.update!(elevation_enrichment_enabled: true)
      expect(described_class.eligible?(course, config:)).to be(true)
    end

    it "never takes a course without provider, already on the terrain, or of a virtual sport" do
      user.update!(elevation_enrichment_enabled: true)

      expect(described_class.eligible?(course, config: unconfigured)).to be(false)
      expect(described_class.eligible?(course(elevation_source: "dem"), config:)).to be(false)
      expect(described_class.eligible?(course(sport: catalog_sport("cycling_virtual")), config:)).to be(false)
    end

    it "matches the backfill scope" do
      public_course = course(visibility: "public")
      private_course = course
      failed = course(visibility: "public", elevation_status: "failed")
      course(visibility: "public", elevation_status: "unavailable")

      expect(described_class.pending_scope).to contain_exactly(public_course, failed)
      user.update!(elevation_enrichment_enabled: true)
      expect(described_class.pending_scope).to include(private_course)
    end
  end

  it "replaces the device figures with the terrain's" do
    segment = apply(course(visibility: "public"))

    expect(segment).to have_attributes(elevation_source: "dem", elevation_status: "ready", ascent: 0.0)
    expect(segment.descent).to be_within(10.0).of(50.0)
    expect(segment.average_grade).to be < -3
    expect(segment.elevation_profile.last["d"]).to be_within(0.5).of(1_000.0)
  end

  it "keeps the device figures when the terrain misses part of the course" do
    allow(client).to receive(:elevations) { |locations| [ nil ] + Array.new(locations.length - 1, 100.0) }

    segment = apply(course(visibility: "public"))

    expect(segment).to have_attributes(elevation_source: "device", elevation_status: "unavailable", ascent: 3.0)
  end

  it "sends nothing for an ineligible course" do
    segment = apply(course)

    expect(client).not_to have_received(:elevations)
    expect(segment).to have_attributes(elevation_source: "device", elevation_status: nil)
  end

  describe "scheduling" do
    include ActiveJob::TestHelper

    before { allow(Allure::Elevation::Config).to receive(:configured?).and_return(true) }

    it "enqueues an eligible new course and a course turning public" do
      clear_enqueued_jobs
      public_course = course(visibility: "public")
      expect(Segments::ApplyTerrainElevationJob).to have_been_enqueued.with(public_course)

      private_course = course
      expect(Segments::ApplyTerrainElevationJob).not_to have_been_enqueued.with(private_course)

      private_course.update!(visibility: "public")
      expect(Segments::ApplyTerrainElevationJob).to have_been_enqueued.with(private_course)
    end
  end
end
