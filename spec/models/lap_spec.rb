# frozen_string_literal: true

require "rails_helper"

RSpec.describe Lap do
  describe "validations" do
    it "requires a lap number of at least one" do
      expect(build(:lap, number: 0)).not_to be_valid
    end

    it "requires a number unique within the workout" do
      lap = create(:lap)
      duplicate = build(:lap, workout: lap.workout, number: lap.number)

      expect(duplicate).not_to be_valid
    end

    it "requires non-negative elapsed and moving time" do
      expect(build(:lap, elapsed_time: -1)).not_to be_valid
      expect(build(:lap, moving_time: -1)).not_to be_valid
    end

    it "requires moving time not to exceed elapsed time" do
      expect(build(:lap, elapsed_time: 30, moving_time: 40)).not_to be_valid
    end

    it "requires non-negative metrics" do
      expect(build(:lap, distance: -1)).not_to be_valid
      expect(build(:lap, ascent: -1)).not_to be_valid
      expect(build(:lap, descent: -1)).not_to be_valid
      expect(build(:lap, average_speed: -1)).not_to be_valid
      expect(build(:lap, max_speed: -1)).not_to be_valid
      expect(build(:lap, average_pace: -1)).not_to be_valid
      expect(build(:lap, average_heart_rate: -1)).not_to be_valid
    end

    it "allows a sparse lap to leave optional metrics nil" do
      expect(build(:lap, :sparse)).to be_valid
    end
  end

  describe "database invariants" do
    it "enforces a positive lap number" do
      expect_constraint(:number, 0, "laps_number")
    end

    it "enforces non-negative elapsed time" do
      expect_constraint(:elapsed_time, -1, "laps_elapsed_time")
    end

    it "enforces the moving-time upper bound" do
      expect_constraint(:moving_time, 91, "laps_moving_time")
    end

    it "enforces non-negative distance, ascent, descent, and speed" do
      expect_constraint(:distance, -1, "laps_non_negative_metrics")
      expect_constraint(:ascent, -1, "laps_non_negative_metrics")
      expect_constraint(:descent, -1, "laps_non_negative_metrics")
      expect_constraint(:average_speed, -1, "laps_non_negative_metrics")
      expect_constraint(:max_speed, -1, "laps_non_negative_metrics")
    end

    it "enforces non-negative physiological metrics" do
      expect_constraint(:average_pace, -1, "laps_physiological_metrics")
      expect_constraint(:average_heart_rate, -1, "laps_physiological_metrics")
      expect_constraint(:max_heart_rate, -1, "laps_physiological_metrics")
      expect_constraint(:average_cadence, -1, "laps_physiological_metrics")
      expect_constraint(:average_power, -1, "laps_physiological_metrics")
    end

    it "enforces number uniqueness per workout" do
      lap = create(:lap)
      duplicate = create(:lap, workout: lap.workout, number: 99)

      expect { duplicate.update_column(:number, lap.number) }
        .to raise_error(ActiveRecord::RecordNotUnique, /workout_id_and_number/)
    end

    it "cascades when its workout is deleted" do
      lap = create(:lap)

      expect { lap.workout.delete }.to change(described_class, :count).by(-1)
    end
  end

  private

  def expect_constraint(column, value, name)
    lap = create(:lap)

    expect do
      described_class.transaction(requires_new: true) { lap.update_column(column, value) }
    end
      .to raise_error(ActiveRecord::StatementInvalid, /#{name}/)
  end
end
