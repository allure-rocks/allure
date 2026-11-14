# frozen_string_literal: true

require "rails_helper"

RSpec.describe Record do
  def build_record(overrides = {})
    user = overrides.delete(:user) || create(:user)
    sport = overrides.delete(:sport) || create(:sport)
    described_class.new({
      user:, sport:,
      record_type: "FD",
      value: 1000,
      workout_started_at: Time.current
    }.merge(overrides))
  end

  describe "validations" do
    it "requires a known record type" do
      expect(build_record(record_type: "XX")).not_to be_valid
    end

    it "requires a non-negative value" do
      expect(build_record(value: -1)).not_to be_valid
    end

    it "requires a workout date for display" do
      expect(build_record(workout_started_at: nil)).not_to be_valid
    end

    it "requires one row per user, sport, and type" do
      record = build_record
      record.save!
      duplicate = build_record(user: record.user, sport: record.sport, record_type: record.record_type)

      expect(duplicate).not_to be_valid
    end
  end

  describe "database invariants" do
    it "enforces the type allowlist" do
      record = build_record
      record.save!

      expect do
        described_class.transaction(requires_new: true) { record.update_column(:record_type, "XX") }
      end.to raise_error(ActiveRecord::StatementInvalid, /records_record_type/)
    end

    it "enforces non-negative values" do
      record = build_record
      record.save!

      expect do
        described_class.transaction(requires_new: true) { record.update_column(:value, -1) }
      end.to raise_error(ActiveRecord::StatementInvalid, /records_value/)
    end

    it "enforces uniqueness per user, sport, and type" do
      record = build_record
      record.save!
      duplicate = build_record(user: record.user, sport: record.sport, record_type: record.record_type)

      expect { duplicate.save!(validate: false) }
        .to raise_error(ActiveRecord::RecordNotUnique, /index_records_on_user_sport_type/)
    end

    it "cascades when its user is deleted" do
      record = build_record
      record.save!

      expect { record.user.destroy! }.to change(described_class, :count).by(-1)
    end

    it "nullifies the workout but survives a direct delete that skips recompute" do
      user = create(:user)
      sport = create(:sport)
      workout = create(:workout, user:, sport:)
      record = described_class.find_by!(user:, sport:, record_type: "FD")
      expect(record.workout).to eq(workout)

      expect { workout.delete }.not_to change(described_class, :count)
      expect(record.reload.workout_id).to be_nil
    end

    it "blocks sport deletion while records reference it" do
      record = build_record
      record.save!

      expect { record.sport.destroy! }.to raise_error(ActiveRecord::DeleteRestrictionError)
    end
  end
end
