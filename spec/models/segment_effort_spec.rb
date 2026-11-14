# frozen_string_literal: true

require "rails_helper"

RSpec.describe SegmentEffort do
  describe "identity and defaults" do
    it "receives a UUID and exposes only its ShortUUID" do
      effort = create(:segment_effort)

      expect(effort.uuid).to match(Allure::ShortId::UUID_PATTERN)
      expect(effort.to_param).to have_attributes(length: 22)
      expect(effort.to_param).not_to eq(effort.id.to_s)
      expect(described_class.find_by_short_id!(effort.to_param)).to eq(effort)
    end

    it "defaults derived flags to false" do
      effort = create(:segment_effort)

      expect(effort.attributes.values_at("personal_best", "anonymous"))
        .to eq([ false, false ])
    end
  end

  describe "validations" do
    it "requires moving time not to exceed elapsed time" do
      expect(build(:segment_effort, moving_time: 51)).not_to be_valid
    end

    it "requires the endpoint index to follow the start index" do
      expect(build(:segment_effort, start_point_index: 1, end_point_index: 1)).not_to be_valid
    end

    it "requires non-negative metrics and indexes" do
      expect(build(:segment_effort, distance: -1)).not_to be_valid
      expect(build(:segment_effort, start_offset_meters: -1)).not_to be_valid
      expect(build(:segment_effort, deviation_meters: -1)).not_to be_valid
      expect(build(:segment_effort, start_point_index: -1)).not_to be_valid
      expect(build(:segment_effort, matcher_version: -1)).not_to be_valid
    end

    it "requires occurrence indexes to be unique within a workout traversal" do
      effort = create(:segment_effort)
      duplicate = build(
        :segment_effort,
        segment: effort.segment,
        workout: effort.workout,
        occurrence_index: effort.occurrence_index
      )

      expect(duplicate).not_to be_valid
    end
  end

  describe "database invariants" do
    it "enforces non-negative occurrence indexes" do
      expect_constraint(:occurrence_index, -1, "segment_efforts_occurrence_index")
    end

    it "enforces positive elapsed time" do
      expect_constraint(:elapsed_time, 0, "segment_efforts_elapsed_time")
    end

    it "enforces the moving-time upper bound" do
      expect_constraint(:moving_time, 51, "segment_efforts_moving_time")
    end

    it "enforces ordered point indexes" do
      expect_constraint(:end_point_index, 0, "segment_efforts_point_indexes")
    end

    it "enforces non-negative distance, ascent, descent, and speed" do
      expect_constraint(:distance, -1, "segment_efforts_non_negative_metrics")
      expect_constraint(:ascent, -1, "segment_efforts_non_negative_metrics")
      expect_constraint(:descent, -1, "segment_efforts_non_negative_metrics")
      expect_constraint(:average_speed, -1, "segment_efforts_non_negative_metrics")
    end

    it "enforces non-negative geometry metrics" do
      expect_constraint(:start_offset_meters, -1, "segment_efforts_geometry_metrics")
      expect_constraint(:deviation_meters, -1, "segment_efforts_geometry_metrics")
    end

    it "enforces non-negative optional metrics" do
      expect_constraint(:average_pace, -1, "segment_efforts_physiological_metrics")
      expect_constraint(:average_heart_rate, -1, "segment_efforts_physiological_metrics")
      expect_constraint(:max_heart_rate, -1, "segment_efforts_physiological_metrics")
      expect_constraint(:average_cadence, -1, "segment_efforts_physiological_metrics")
      expect_constraint(:average_power, -1, "segment_efforts_physiological_metrics")
      expect_constraint(:max_power, -1, "segment_efforts_physiological_metrics")
    end

    it "enforces traversal uniqueness in the database" do
      effort = create(:segment_effort)
      duplicate = create(:segment_effort, segment: effort.segment, workout: effort.workout, occurrence_index: 1)

      expect { duplicate.update_column(:occurrence_index, effort.occurrence_index) }
        .to raise_error(ActiveRecord::RecordNotUnique, /segment_id_workout_id_occurrence_index/)
    end

    it "has the partial personal-best index, one best per sport" do
      index = described_class.connection.indexes(:segment_efforts).find do |candidate|
        candidate.columns == [ "segment_id", "user_id", "sport_id" ]
      end

      expect(index.where).to match(/personal_best/)
    end

    it "has the per-sport leaderboard ordering index" do
      index = described_class.connection.indexes(:segment_efforts).find do |candidate|
        candidate.columns == [ "segment_id", "sport_id", "elapsed_time" ]
      end

      expect(index).to be_present
    end

    it "cascades when its segment is deleted" do
      effort = create(:segment_effort)

      expect { effort.segment.delete }.to change(described_class, :count).by(-1)
    end

    it "cascades when its workout is deleted" do
      effort = create(:segment_effort)

      expect { effort.workout.delete }.to change(described_class, :count).by(-1)
    end
  end

  private

  def expect_constraint(column, value, name)
    effort = create(:segment_effort)

    expect do
      described_class.transaction(requires_new: true) { effort.update_column(column, value) }
    end
      .to raise_error(ActiveRecord::StatementInvalid, /#{name}/)
  end
end
