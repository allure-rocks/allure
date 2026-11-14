class AddRejectToOutboxActivityTypes < ActiveRecord::Migration[8.1]
  ACTIVITY_TYPES = %w[Create Delete Undo Follow Accept Like Reject].freeze
  PREVIOUS_TYPES = %w[Create Delete Undo Follow Accept Like].freeze

  def up
    replace_activity_type_constraint(ACTIVITY_TYPES)
  end

  def down
    replace_activity_type_constraint(PREVIOUS_TYPES)
  end

  private

  def replace_activity_type_constraint(types)
    remove_check_constraint :federation_outbox_events, name: "outbox_activity_type"
    add_check_constraint :federation_outbox_events,
                         "activity_type IN (#{types.map { |type| connection.quote(type) }.join(', ')})",
                         name: "outbox_activity_type"
  end
end
