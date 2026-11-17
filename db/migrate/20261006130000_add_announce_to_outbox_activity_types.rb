# frozen_string_literal: true

# docs/dev/COMMENTS.md: the thread host relays every accepted public
# comment as an Announce, the one activity type the comments relay adds.
class AddAnnounceToOutboxActivityTypes < ActiveRecord::Migration[8.1]
  ACTIVITY_TYPES = %w[Create Delete Undo Follow Accept Like Reject Announce].freeze
  PREVIOUS_TYPES = %w[Create Delete Undo Follow Accept Like Reject].freeze

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
