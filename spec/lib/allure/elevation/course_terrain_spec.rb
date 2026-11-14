# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Elevation::CourseTerrain do
  # About 1.1 km due east at the equator.
  let(:coordinates) { [ [ 0.0, 0.0 ], [ 0.005, 0.0 ], [ 0.01, 0.0 ] ] }

  describe ".samples" do
    it "samples a short course every 20 m at least, endpoints included" do
      samples = described_class.samples(coordinates, interval_metres: 50.0, max_requests: 10)

      expect(samples.first.distance).to eq(0.0)
      expect(samples.last.distance).to be_within(1.0).of(1_113.2)
      expect(samples.length).to be_between(50, 60)
    end

    it "coarsens the interval until the samples fit the request budget" do
      long = [ [ 0.0, 0.0 ], [ 1.0, 0.0 ] ]
      samples = described_class.samples(long, interval_metres: 50.0, max_requests: 2)

      expect(Allure::Elevation::Sampler.chunks(samples).length).to be <= 2
    end
  end

  describe ".metrics" do
    let(:samples) { described_class.samples(coordinates, interval_metres: 50.0, max_requests: 10) }

    it "measures a steady descent from the terrain, signed grade and profile on the course distance" do
      elevations = samples.map { |sample| 200.0 - (sample.distance * 0.08) }

      result = described_class.metrics(samples, elevations, distance: 1_100.0)

      expect(result.ascent).to eq(0.0)
      # The 8 m terrain threshold leaves out the last unfinished step.
      expect(result.descent).to be_between(75.0, 89.5)
      expect(result.average_grade).to be < -6.0
      expect(result.profile.last["d"]).to be_within(0.5).of(1_100.0)
      expect(result.max_elevation).to be > result.min_elevation
    end

    it "refuses a profile the terrain did not answer in full" do
      elevations = samples.map { 100.0 }
      elevations[3] = nil

      expect(described_class.metrics(samples, elevations, distance: 1_100.0)).to be_nil
    end
  end
end
