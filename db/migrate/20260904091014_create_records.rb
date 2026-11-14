class CreateRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :records do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :sport, null: false, foreign_key: true, index: false
      t.references :workout, foreign_key: { on_delete: :nullify }, index: false
      t.datetime :workout_started_at, null: false
      t.string :record_type, null: false
      t.decimal :value, precision: 20, scale: 6, null: false

      t.timestamps
    end

    add_index :records, [ :user_id, :sport_id, :record_type ], unique: true, name: "index_records_on_user_sport_type"
    add_index :records, [ :workout_id, :record_type ], name: "index_records_on_workout_type"

    add_check_constraint :records,
                         "record_type IN ('AP', 'AS', 'BP', 'FD', 'HA', 'LD', 'MS')",
                         name: "records_record_type"
    add_check_constraint :records, "value >= 0", name: "records_value"
  end
end
