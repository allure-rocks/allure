# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Heart-rate profile" do
  describe User do
    let(:user) { build(:user) }

    def error_codes(record, attribute)
      record.valid?
      record.errors.details[attribute].map { it[:error] }
    end

    it "has no zones until a maximum is set" do
      expect(user.heart_rate_zones).to be_nil

      user.max_heart_rate = 185
      expect(user.heart_rate_zones.thresholds).to eq([ 111, 130, 148, 167 ])
    end

    it "validates the ranges, the order and the bounds" do
      user.assign_attributes(max_heart_rate: 230)
      expect(user).not_to be_valid

      user.assign_attributes(max_heart_rate: 180, resting_heart_rate: 180)
      expect(error_codes(user, :resting_heart_rate)).to include(:not_below_maximum)

      user.assign_attributes(resting_heart_rate: 50, heart_rate_zone_bounds: [ 60, 60, 80, 90 ])
      expect(error_codes(user, :heart_rate_zone_bounds)).to include(:invalid_bounds)

      user.assign_attributes(heart_rate_zone_bounds: [ 60, 70, 80, 100 ])
      expect(error_codes(user, :heart_rate_zone_bounds)).to include(:invalid_bounds)

      user.assign_attributes(heart_rate_zone_bounds: [ 55, 72, 82, 92 ])
      expect(user).to be_valid
    end

    it "needs a resting value for reserve zones" do
      user.assign_attributes(max_heart_rate: 180, heart_rate_zone_basis: "reserve")

      expect(error_codes(user, :resting_heart_rate)).to include(:required_for_reserve)
    end

    it "refuses bounds that leave a zone without a single bpm" do
      # A 10-bpm reserve: 61 % and 62 % both round to 116 bpm.
      user.assign_attributes(max_heart_rate: 120, resting_heart_rate: 110, heart_rate_zone_basis: "reserve",
                             heart_rate_zone_bounds: [ 50, 61, 62, 90 ])

      expect(error_codes(user, :heart_rate_zone_bounds)).to include(:indistinct)
    end

    it "is enforced by the database too" do
      saved = create(:user)

      expect { saved.update_columns(heart_rate_zone_bounds: [ 60, 70 ]) }.to raise_error(ActiveRecord::StatementInvalid)
    end
  end

  describe WorkoutHeartRate do
    let(:user) { create(:user, max_heart_rate: 190) }
    let(:histogram) { Array.new(191, 0).tap { it[150 - 30] = 600 } }

    it "slices on the fly while the stored zones are stale" do
      row = described_class.create!(workout: create(:workout, user:), version: 1, histogram:,
                                    sampled_seconds: 600, recorded_seconds: 600, covered_seconds: 600)

      expect(row.zone_seconds).to be_nil
      expect(row.zone_seconds_for(user.heart_rate_zones)).to eq([ 0, 0, 600, 0, 0 ])
      expect(row.load_for(user.heart_rate_zones)).to eq(30.0)
      expect(row).to be_usable
    end

    it "reads coverage against the recorded time, pauses excluded, and refuses a sparse recording" do
      row = described_class.new(workout: create(:workout, user:), version: 2, histogram:,
                                sampled_seconds: 600, recorded_seconds: 3600, covered_seconds: 900)

      expect(row.coverage).to be_within(0.001).of(600.0 / 900)
      expect(row).to be_usable
      expect(described_class.usable.to_sql).to include("covered_seconds")

      row.sparse = true
      expect(row).not_to be_usable
      expect(row.unusable_reason).to eq(:sparse)
    end

    it "belongs to recordings only" do
      row = described_class.new(workout: create(:workout, :manual, user:), version: 1, histogram:,
                                sampled_seconds: 600, recorded_seconds: 600, covered_seconds: 600)

      expect(row).not_to be_valid
    end
  end
end
