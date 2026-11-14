# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Stats::RobustTrend do
  let(:week) { 7 * 86_400.0 }

  def line(xs, intercept:, slope:)
    xs.map { |x| intercept + slope * x }
  end

  describe "under eight points (Theil–Sen)" do
    it "recovers aligned points exactly" do
      xs = [ 0, 1, 2, 3 ].map { it * week }

      expect(described_class.fit(xs, line(xs, intercept: 300, slope: -5 / week)))
        .to match([ 300, 295, 290, 285 ].map { be_within(1e-9).of(it) })
    end

    it "ignores one outlier among five" do
      xs = [ 0, 1, 2, 3, 4 ].map { it * week }

      expect(described_class.fit(xs, [ 300, 295, 290, 400, 280 ]))
        .to match([ 300, 295, 290, 285, 280 ].map { be_within(1e-9).of(it) })
    end

    it "is flat at the median when every point shares one x" do
      expect(described_class.fit([ 0, 0, 0 ], [ 300, 280, 310 ])).to eq([ 300.0, 300.0, 300.0 ])
    end
  end

  describe "from eight points (robust LOWESS)" do
    it "reproduces a line exactly, even irregularly spaced" do
      xs = [ 0, 0.2, 0.3, 0.5, 9, 9.5, 20, 21, 22, 40 ].map { it * week }
      ys = line(xs, intercept: 320, slope: -1.5 / week)

      expect(described_class.fit(xs, ys)).to match(ys.map { be_within(1e-6).of(it) })
    end

    it "does not flatten the ends of a trend" do
      xs = (0...12).map { it * week }
      ys = line(xs, intercept: 280, slope: 2 / week)

      fitted = described_class.fit(xs, ys)
      expect(fitted.first).to be_within(1e-6).of(280)
      expect(fitted.last).to be_within(1e-6).of(302)
    end

    it "barely moves for an outlier" do
      xs = (0...12).map { it * week }
      ys = line(xs, intercept: 300, slope: -1 / week)
      ys[6] += 120

      expect(described_class.fit(xs, ys)[6]).to be_within(1).of(294)
    end

    it "smooths alternating noise around the trend" do
      xs = (0...20).map { it * week }
      ys = xs.each_with_index.map { |x, index| 300 - x / week + (index.even? ? 10 : -10) }

      fitted = described_class.fit(xs, ys)
      expect(fitted.each_with_index.map { |value, index| (value - (300 - index)).abs }.max).to be < 4
    end

    it "follows a change of direction in a long history" do
      xs = (0...120).map { it * week }
      ys = xs.each_index.map { |index| 300 - 20 * Math.sin(index * Math::PI / 60) }

      fitted = described_class.fit(xs, ys)
      expect(fitted[30]).to be < fitted[0] - 10
      expect(fitted[90]).to be > fitted[30] + 30
    end

    it "copes with shared x and constant values" do
      xs = [ 0, 0, 0, 1, 1, 2, 2, 3 ].map { it * week }

      expect(described_class.fit(xs, Array.new(8, 300))).to all(be_within(1e-9).of(300))
      expect(described_class.fit(xs, [ 300, 310, 290, 305, 295, 300, 302, 298 ])).to all(be_finite)
    end

    it "stays close to an unaccelerated fit when it interpolates" do
      xs = (0...200).map { |index| (index + (index % 3) * 0.004) * 86_400.0 }
      ys = xs.each_index.map { |index| 300 + 10 * Math.sin(index / 15.0) + (index % 5) }

      accelerated = described_class.fit(xs, ys)
      stub_const("#{described_class}::DELTA_FRACTION", 0.0)
      exact = described_class.fit(xs, ys)
      expect(accelerated.zip(exact).map { |a, b| (a - b).abs }.max).to be < 0.5
    end
  end

  describe ".fit_at" do
    it "matches the fit at the data positions" do
      [ 6, 25 ].each do |size|
        xs = (0...size).map { |index| (index * 1.7 + (index % 3)) * week }
        ys = xs.each_index.map { |index| 300 + 10 * Math.sin(index / 4.0) + (index % 4) }

        expect(described_class.fit_at(xs, ys, xs)).to match(described_class.fit(xs, ys).map { be_within(0.5).of(it) })
      end
    end

    it "extends a Theil–Sen line to any position" do
      xs = [ 0, 1, 2, 3 ].map { it * week }

      expect(described_class.fit_at(xs, line(xs, intercept: 300, slope: -5 / week), [ 1.5 * week, 10 * week ]))
        .to match([ 292.5, 250 ].map { be_within(1e-9).of(it) })
    end

    it "stays between the neighbouring fits across a long gap" do
      xs = (0...20).map { it * week } + [ 120 * week ]
      ys = xs.map { |x| 300 - x / week * 0.5 }
      grid = (0..100).map { |step| 120 * week * step / 100 }

      fitted = described_class.fit_at(xs, ys, grid)
      expect(fitted.each_cons(2).map { |a, b| (b - a).abs }.max).to be < 2
    end

    it "is empty without data" do
      expect(described_class.fit_at([], [], [ 0 ])).to eq([])
    end
  end

  it "refuses series of different sizes" do
    expect { described_class.fit([ 0, 1 ], [ 300 ]) }.to raise_error(ArgumentError)
  end
end
