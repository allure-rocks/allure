# frozen_string_literal: true

require "rails_helper"

RSpec.describe EquipmentType do
  it "requires a unique slug and a label" do
    expect(build(:equipment_type, slug: nil)).not_to be_valid
    expect(build(:equipment_type, label: nil)).not_to be_valid

    create(:equipment_type, slug: "spec-bike")
    expect(build(:equipment_type, slug: "spec-bike")).not_to be_valid
  end

  it "requires an active flag" do
    expect(build(:equipment_type, is_active: nil)).not_to be_valid
  end

  it "blocks deletion while equipments reference it" do
    type = create(:equipment_type)
    create(:equipment, equipment_type: type)

    expect { type.destroy! }.to raise_error(ActiveRecord::DeleteRestrictionError)
  end
end
