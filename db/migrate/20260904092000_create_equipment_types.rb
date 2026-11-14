class CreateEquipmentTypes < ActiveRecord::Migration[8.1]
  def change
    create_table :equipment_types do |t|
      t.string :slug, null: false
      t.string :label, null: false
      t.boolean :is_active, null: false, default: true

      t.timestamps
    end

    add_index :equipment_types, :slug, unique: true
  end
end
