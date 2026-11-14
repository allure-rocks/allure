class CreateWorkoutEquipments < ActiveRecord::Migration[8.1]
  def change
    create_table :workout_equipments, id: false do |t|
      t.references :workout, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :equipment, null: false, foreign_key: { to_table: :equipments, on_delete: :cascade }, index: false
    end

    add_index :workout_equipments, [ :workout_id, :equipment_id ],
              unique: true, name: "index_workout_equipments_on_workout_and_equipment"
    add_index :workout_equipments, [ :equipment_id, :workout_id ],
              name: "index_workout_equipments_on_equipment_and_workout"
  end
end
