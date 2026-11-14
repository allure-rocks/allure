# frozen_string_literal: true

require "rails_helper"

RSpec.describe Equipment do
  describe "validations" do
    it "requires a short unique-per-user label" do
      expect(build(:equipment, label: nil)).not_to be_valid
      expect(build(:equipment, label: "")).not_to be_valid
      expect(build(:equipment, label: "x" * 51)).not_to be_valid

      existing = create(:equipment)
      expect(build(:equipment, user: existing.user, label: existing.label)).not_to be_valid
      expect(build(:equipment, label: existing.label)).to be_valid
    end

    it "allows a missing description but caps its length" do
      expect(build(:equipment, description: nil)).to be_valid
      expect(build(:equipment, description: "x" * 2001)).not_to be_valid
    end

    it "requires an active flag and non-negative totals" do
      expect(build(:equipment, is_active: nil)).not_to be_valid
      expect(build(:equipment, total_distance: -1)).not_to be_valid
      expect(build(:equipment, total_duration: -1)).not_to be_valid
      expect(build(:equipment, total_moving: -1)).not_to be_valid
      expect(build(:equipment, total_workouts: -1)).not_to be_valid
    end

    it "assigns a UUID and exposes only its ShortUUID" do
      equipment = create(:equipment)

      expect(equipment.uuid).to match(Allure::ShortId::UUID_PATTERN)
      expect(equipment.to_param).to have_attributes(length: 22)
    end
  end

  describe "database invariants" do
    it "enforces non-negative totals" do
      equipment = create(:equipment)

      expect do
        described_class.transaction(requires_new: true) { equipment.update_column(:total_distance, -1) }
      end.to raise_error(ActiveRecord::StatementInvalid, /equipments_non_negative_totals/)
    end

    it "enforces label uniqueness per user" do
      equipment = create(:equipment)

      expect do
        described_class.transaction(requires_new: true) do
          build(:equipment, user: equipment.user, label: equipment.label).save!(validate: false)
        end
      end.to raise_error(ActiveRecord::RecordNotUnique, /user_id.*label|label.*user_id/)
    end

    it "cascades when its user is deleted" do
      equipment = create(:equipment)

      expect { equipment.user.destroy! }.to change(described_class, :count).by(-1)
    end

    it "links and unlinks workouts through the join table" do
      equipment = create(:equipment)
      workout = create(:workout, user: equipment.user)

      expect { equipment.workouts << workout }.to change { equipment.workouts.count }.by(1)
      expect { equipment.workouts.delete(workout) }.to change { equipment.workouts.count }.by(-1)
    end
  end
end
