# frozen_string_literal: true

require "rails_helper"

RSpec.describe Equipments::Totals do
  let(:user) { create(:user) }

  def create_workout(distance:, moving:)
    create(:workout, user:, distance:, moving_time: moving, duration: moving + 100, pause_time: 100)
  end

  def totals(equipment)
    equipment.reload.attributes.values_at("total_distance", "total_duration", "total_moving", "total_workouts")
  end

  describe ".sync" do
    it "leaves links untouched on nil" do
      equipment = create(:equipment, user:)
      workout = create_workout(distance: 1000, moving: 600)

      expect { described_class.sync(workout, nil) }.not_to(change { workout.equipment_ids })
      expect(totals(equipment)).to eq([ 0, 0, 0, 0 ])
    end

    it "attaches new active equipment and increments totals" do
      equipment = create(:equipment, user:)
      workout = create_workout(distance: 1000, moving: 600)

      described_class.sync(workout, [ equipment.id ])

      expect(workout.equipment_ids).to eq([ equipment.id ])
      expect(totals(equipment)).to eq([ 1000, 600, 600, 1 ])
    end

    it "clears on empty array" do
      equipment = create(:equipment, user:)
      workout = create_workout(distance: 1000, moving: 600)
      described_class.sync(workout, [ equipment.id ])

      described_class.sync(workout, [])

      expect(workout.equipment_ids).to be_empty
      expect(totals(equipment)).to eq([ 0, 0, 0, 0 ])
    end

    it "detaches removed links and decrements" do
      kept = create(:equipment, user:)
      dropped = create(:equipment, user:)
      workout = create_workout(distance: 1000, moving: 600)
      described_class.sync(workout, [ kept.id, dropped.id ])

      described_class.sync(workout, [ kept.id ])

      expect(workout.equipment_ids).to eq([ kept.id ])
      expect(totals(kept)).to eq([ 1000, 600, 600, 1 ])
      expect(totals(dropped)).to eq([ 0, 0, 0, 0 ])
    end

    it "silently ignores foreign equipment IDs" do
      foreign = create(:equipment)
      workout = create_workout(distance: 1000, moving: 600)

      expect { described_class.sync(workout, [ foreign.id ]) }.not_to raise_error
      expect(workout.equipment_ids).to be_empty
      expect(totals(foreign)).to eq([ 0, 0, 0, 0 ])
    end

    it "rejects newly attached inactive equipment but preserves re-submitted inactive" do
      equipment = create(:equipment, :inactive, user:)
      workout = create_workout(distance: 1000, moving: 600)

      described_class.sync(workout, [ equipment.id ])
      expect(workout.equipment_ids).to be_empty
      expect(totals(equipment)).to eq([ 0, 0, 0, 0 ])

      equipment.update!(is_active: true)
      described_class.sync(workout, [ equipment.id ])
      equipment.update!(is_active: false)
      described_class.sync(workout, [ equipment.id ])

      expect(workout.equipment_ids).to eq([ equipment.id ])
      expect(totals(equipment)).to eq([ 1000, 600, 600, 1 ])

      described_class.sync(workout, [])
      expect(workout.equipment_ids).to be_empty
      expect(totals(equipment)).to eq([ 0, 0, 0, 0 ])
    end
  end

  describe ".diff" do
    it "adjusts totals for a metric change without touching the count" do
      equipment = create(:equipment, user:)
      workout = create_workout(distance: 1000, moving: 600)
      described_class.sync(workout, [ equipment.id ])

      described_class.diff(equipment, old_distance: 1000, old_moving: 600, new_distance: 2000, new_moving: 900)

      expect(totals(equipment)).to eq([ 2000, 900, 900, 1 ])
    end
  end

  describe ".refresh" do
    it "repairs drifted totals from the attached workouts" do
      equipment = create(:equipment, user:)
      workout = create_workout(distance: 1000, moving: 600)
      described_class.sync(workout, [ equipment.id ])
      equipment.update_columns(total_distance: 99999, total_workouts: 99)

      described_class.refresh(equipment)

      expect(totals(equipment)).to eq([ 1000, 600, 600, 1 ])
    end

    it "zeroes totals with no attached workouts" do
      equipment = create(:equipment, user:)
      equipment.update_columns(total_distance: 100, total_workouts: 1)

      described_class.refresh(equipment)

      expect(totals(equipment)).to eq([ 0, 0, 0, 0 ])
    end
  end

  describe "decrement clamp" do
    it "floors at zero instead of violating the check" do
      equipment = create(:equipment, user:)
      workout = create_workout(distance: 1000, moving: 600)
      equipment.update_columns(total_distance: 100, total_duration: 100, total_moving: 100, total_workouts: 1)

      described_class.decrement(equipment, workout)

      expect(totals(equipment)).to eq([ 0, 0, 0, 0 ])
    end
  end
end
