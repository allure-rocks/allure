# frozen_string_literal: true

# Publication Create intents wait as `preparing` while the async route image
# renders, so federation sends the Note with its media. The existing status
# check must allow the new value.
class AllowPreparingOutboxStatus < ActiveRecord::Migration[8.1]
  def up
    remove_check_constraint :federation_outbox_events, name: "outbox_status"
    add_check_constraint :federation_outbox_events,
                         "status IN ('preparing', 'pending', 'expanded', 'complete', 'cancelled', 'failed')",
                         name: "outbox_status"
  end

  def down
    remove_check_constraint :federation_outbox_events, name: "outbox_status"
    add_check_constraint :federation_outbox_events,
                         "status IN ('pending', 'expanded', 'complete', 'cancelled', 'failed')",
                         name: "outbox_status"
  end
end
