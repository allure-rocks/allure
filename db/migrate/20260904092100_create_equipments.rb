class CreateEquipments < ActiveRecord::Migration[8.1]
  def change
    create_table :equipments do |t|
      t.uuid :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :label, null: false
      t.string :description
      t.references :equipment_type, null: false, foreign_key: true, index: false
      t.boolean :is_active, null: false, default: true
      t.decimal :total_distance, precision: 14, scale: 3, null: false, default: 0
      t.integer :total_duration, null: false, default: 0
      t.integer :total_moving, null: false, default: 0
      t.integer :total_workouts, null: false, default: 0

      t.timestamps
    end

    add_index :equipments, :uuid, unique: true
    add_index :equipments, [ :user_id, :label ], unique: true
    add_index :equipments, :user_id
    add_index :equipments, :equipment_type_id

    add_check_constraint :equipments,
                         "total_distance >= 0 AND total_duration >= 0 AND total_moving >= 0 AND total_workouts >= 0",
                         name: "equipments_non_negative_totals"
  end
end
