# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Gpx::Elevation do
  describe ".valid?" do
    it "accepts 0.0 as valid" do
      expect(described_class.valid?(0.0)).to be(true)
    end

    it "rejects nil, NaN, infinity, and out-of-range values" do
      expect(described_class.valid?(nil)).to be(false)
      expect(described_class.valid?(Float::NAN)).to be(false)
      expect(described_class.valid?(Float::INFINITY)).to be(false)
      expect(described_class.valid?(9999.99)).to be(false)
      expect(described_class.valid?(-9999.99)).to be(false)
      expect(described_class.valid?(9999.98)).to be(true)
      expect(described_class.valid?(-9999.98)).to be(true)
    end
  end

  describe ".minimum and .maximum" do
    it "ignore invalid values" do
      elevations = [ 100.0, nil, -20000.0, 150.0 ]
      expect(described_class.minimum(elevations)).to eq(100.0)
      expect(described_class.maximum(elevations)).to eq(150.0)
    end
  end

  describe ".filter" do
    it "removes an isolated elevation spike" do
      elevations = [ 100.0, 100.0, 120.0, 100.0, 100.0 ]
      distances = [ 0.0, 1.0, 2.0, 3.0, 4.0 ]

      expect(described_class.filter(elevations, distances:)).to eq([ 100.0, 100.0, 100.0, 100.0, 100.0 ])
    end

    it "leaves a coarse track whose samples are farther apart than the window untouched" do
      elevations = [ 2000.0, 2050.0, 2120.0, 2100.0 ]
      distances = [ 0.0, 120.0, 240.0, 360.0 ]

      expect(described_class.filter(elevations, distances:)).to eq(elevations)
    end

    it "never bridges a missing value" do
      elevations = [ 100.0, 105.0, nil, 200.0, 190.0 ]
      distances = [ 0.0, 1.0, 2.0, 3.0, 4.0 ]

      filtered = described_class.filter(elevations, distances:)

      expect(filtered[2]).to be_nil
      expect(filtered[0]).to be_within(0.0001).of(102.5)
      expect(filtered[1]).to be_within(0.0001).of(102.5)
      expect(filtered[3]).to be_within(0.0001).of(195.0)
      expect(filtered[4]).to be_within(0.0001).of(195.0)
    end
  end

  describe ".noise_sigma and .noise_class" do
    it "recovers a large sigma from a noisy profile" do
      elevations = [ 100.0, 101.0, 100.0, 101.0, 100.0, 101.0 ]
      distances = [ 0.0, 1.0, 2.0, 3.0, 4.0, 5.0 ]

      expect(described_class.noise_sigma(elevations, distances:)).to be_within(0.0001).of(0.62665)
      expect(described_class.noise_class(elevations, distances:)).to eq(:gps)
    end

    it "classifies a clean barometric profile" do
      elevations = [ 100.0, 100.2, 100.0, 100.2, 100.0 ]
      distances = [ 0.0, 1.0, 2.0, 3.0, 4.0 ]

      expect(described_class.noise_sigma(elevations, distances:)).to be < described_class::BAROMETRIC_SIGMA_METRES
      expect(described_class.noise_class(elevations, distances:)).to eq(:barometric)
    end
  end

  describe ".threshold_for" do
    it "selects the barometric and GPS thresholds" do
      expect(described_class.threshold_for(:barometric)).to eq(1.0)
      expect(described_class.threshold_for(:gps)).to eq(3.0)
      expect(described_class.threshold_for(nil)).to eq(3.0)
    end
  end

  describe ".ascent_and_descent" do
    it "counts an excursion once its net change reaches the threshold" do
      ascent, descent = described_class.ascent_and_descent([ 100.0, 105.0, 100.0 ], threshold: 3.0)
      expect(ascent).to be_within(0.0001).of(5.0)
      expect(descent).to be_within(0.0001).of(5.0)
    end

    it "adds the whole excursion, not only the excess" do
      ascent, descent = described_class.ascent_and_descent([ 100.0, 102.0, 104.0, 106.0 ], threshold: 3.0)
      expect(ascent).to be_within(0.0001).of(4.0)
      expect(descent).to eq(0.0)
    end

    it "ignores sub-threshold wiggle" do
      ascent, descent = described_class.ascent_and_descent([ 100.0, 101.0, 102.0, 101.0 ], threshold: 3.0)
      expect(ascent).to eq(0.0)
      expect(descent).to eq(0.0)
    end

    it "never bridges a missing value with an artificial climb" do
      ascent, descent = described_class.ascent_and_descent([ 100.0, 105.0, nil, 200.0, 190.0 ], threshold: 3.0)
      expect(ascent).to be_within(0.0001).of(5.0)
      expect(descent).to be_within(0.0001).of(10.0)
    end

    it "contributes nothing for an isolated single-point run" do
      ascent, descent = described_class.ascent_and_descent([ 100.0, nil, 105.0, nil, 100.0 ], threshold: 3.0)
      expect(ascent).to eq(0.0)
      expect(descent).to eq(0.0)
    end

    it "treats sea level as a valid, non-missing elevation" do
      ascent, descent = described_class.ascent_and_descent([ 0.0, 0.0, 0.0 ], threshold: 1.0)
      expect(ascent).to eq(0.0)
      expect(descent).to eq(0.0)
    end
  end

  describe ".threshold_for" do
    it "maps every persisted class, defaulting to the conservative GPS threshold" do
      expect(described_class.threshold_for("barometric")).to eq(1.0)
      expect(described_class.threshold_for("gps")).to eq(3.0)
      expect(described_class.threshold_for("dem")).to eq(8.0)
      expect(described_class.threshold_for(nil)).to eq(3.0)
      expect(described_class.threshold_for("unknown")).to eq(3.0)
    end
  end

  describe ".filter with the DEM class" do
    it "smooths with a wider window than the GPS class" do
      elevations = [ 100.0, 120.0, 100.0 ]
      distances = [ 0.0, 60.0, 120.0 ]

      gps = described_class.filter(elevations, distances:, noise_class: :gps)
      dem = described_class.filter(elevations, distances:, noise_class: :dem)

      expect(dem[1]).to be < gps[1]
      expect(dem[1]).to be_within(0.0001).of(106.66666666666667)
    end
  end
end
