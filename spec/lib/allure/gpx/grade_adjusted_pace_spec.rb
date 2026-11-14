# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Gpx::GradeAdjustedPace do
  let(:point_class) { Data.define(:time, :longitude, :latitude, :elevation) }

  # Roughly 1 000 m of latitude at 45° N, so a pair of points a "step" apart
  # walks about a kilometre.
  def lat_step = 0.008983

  def point(time:, lat: 45.0, lon: 6.0, elevation: nil)
    point_class.new(time:, longitude: lon, latitude: lat, elevation:)
  end

  def flat_pair(seconds:, elevation: 100.0)
    [ point(time: 0, elevation:), point(time: seconds, lat: 45.0 + lat_step, elevation:) ]
  end

  describe "adjustment_factor" do
    it "is 1.0 on flat ground" do
      expect(described_class.adjustment_factor(0.0)).to eq(1.0)
    end

    it "is above 1.0 uphill (more adjusted distance, faster GAP)" do
      expect(described_class.adjustment_factor(0.05)).to be > 1.0
    end

    it "is 0.88 at the -9 % descent minimum" do
      expect(described_class.adjustment_factor(-0.09)).to be_within(0.001).of(0.88)
    end

    it "returns to 1.0 by -18 % (no further benefit)" do
      expect(described_class.adjustment_factor(-0.18)).to eq(1.0)
    end

    it "stays 1.0 below -18 % (braking)" do
      expect(described_class.adjustment_factor(-0.25)).to eq(1.0)
    end

    it "is bounded by +45 %" do
      factor = described_class.adjustment_factor(0.45)
      expect(factor).to be > 1.0
      expect(described_class.adjustment_factor(0.5)).to eq(factor)
    end
  end

  describe "grade_adjusted_pace" do
    context "flat terrain" do
      it "returns the actual pace" do
        expect(described_class.grade_adjusted_pace(flat_pair(seconds: 200), stopped_speed_threshold_km_h: 0.5)).to eq(200)
      end
    end

    context "uphill" do
      it "returns a faster pace than the actual pace" do
        points = [
          point(time: 0, elevation: 100.0),
          point(time: 200, lat: 45.0 + lat_step, elevation: 150.0)
        ]
        gap = described_class.grade_adjusted_pace(points, stopped_speed_threshold_km_h: 0.5)
        expect(gap).to be < 200
      end
    end

    context "downhill" do
      it "returns a slower pace than the actual pace for a moderate slope" do
        points = [
          point(time: 0, elevation: 100.0),
          point(time: 180, lat: 45.0 + lat_step, elevation: 50.0)
        ]
        expect(described_class.grade_adjusted_pace(points, stopped_speed_threshold_km_h: 0.5)).to be > 180
      end

      it "is close to the actual pace on a steep slope beyond -18 %" do
        points = [
          point(time: 0, elevation: 100.0),
          point(time: 100, lat: 45.0 + lat_step, elevation: -80.0)
        ]
        # Actual pace is already slightly under 100 s/km because the 3D
        # distance exceeds the horizontal kilometre; a neutral factor keeps
        # GAP equal to it.
        expect(described_class.grade_adjusted_pace(points, stopped_speed_threshold_km_h: 0.5)).to be_within(3).of(98)
      end
    end

    context "missing elevation" do
      it "returns nil when no endpoint carries elevation" do
        points = [
          point(time: 0),
          point(time: 200, lat: 45.0 + lat_step)
        ]
        expect(described_class.grade_adjusted_pace(points, stopped_speed_threshold_km_h: 0.5)).to be_nil
      end

      it "returns nil when fewer than two points are given" do
        expect(described_class.grade_adjusted_pace([ point(time: 0, elevation: 100.0) ], stopped_speed_threshold_km_h: 0.5)).to be_nil
      end
    end

    context "stopped intervals are excluded" do
      it "ignores intervals below the stopped-speed threshold" do
        points = [
          point(time: 0, elevation: 100.0),
          point(time: 10_000, lat: 45.0 + 0.000001, elevation: 150.0)
        ]
        expect(described_class.grade_adjusted_pace(points, stopped_speed_threshold_km_h: 0.5)).to be_nil
      end
    end
  end

  describe "from_points" do
    it "returns nil when there is no eligible moving interval" do
      points = [
        point(time: 0, elevation: 100.0),
        point(time: 10_000, lat: 45.0 + 0.000001, elevation: 150.0)
      ]
      expect(described_class.from_points(points, stopped_speed_threshold_km_h: 0.5)).to be_nil
    end

    it "returns nil for a positionless recording instead of crashing (PLAN_NO_GPS.md §4)" do
      points = [
        point(time: 0, lat: nil, lon: nil, elevation: 100.0),
        point(time: 200, lat: nil, lon: nil, elevation: 100.0)
      ]

      expect(described_class.from_points(points, stopped_speed_threshold_km_h: 0.5)).to be_nil
    end

    it "returns the adjusted distance and moving time for eligible intervals" do
      result = described_class.from_points(flat_pair(seconds: 200), stopped_speed_threshold_km_h: 0.5)
      expect(result[:grade_adjusted_distance]).to be_within(1.0).of(1000.0)
      expect(result[:moving_time]).to eq(200)
    end
  end
end
