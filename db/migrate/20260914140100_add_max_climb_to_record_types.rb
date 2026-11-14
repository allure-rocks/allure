# frozen_string_literal: true

# `MC` (biggest climb) joins the seven workout-column records. The winner is
# the workout holding the largest detected climb, so the recompute reads
# `detected_laps` rather than a workout column.
class AddMaxClimbToRecordTypes < ActiveRecord::Migration[8.1]
  TYPES = %w[AP AS BP FD HA LD MS MC].freeze
  LEGACY_TYPES = %w[AP AS BP FD HA LD MS].freeze

  def up
    replace_type_constraint(TYPES)
  end

  def down
    execute "DELETE FROM records WHERE record_type = 'MC'"
    replace_type_constraint(LEGACY_TYPES)
  end

  private

  def replace_type_constraint(types)
    remove_check_constraint :records, name: "records_record_type"
    add_check_constraint :records, "record_type IN (#{quoted(types)})", name: "records_record_type"
  end

  def quoted(types) = types.map { |type| "'#{type}'" }.join(", ")
end
