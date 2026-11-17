# frozen_string_literal: true

# docs/dev/COMMENTS.md: what a relayed comment remembers. A third
# party's comment records the host whose Announce delivered it and that
# Announce's identity, so the host's Undo finds it; this instance's own comment
# coming back in the host's Announce records when the host confirmed it.
class AddRelayToComments < ActiveRecord::Migration[8.1]
  def change
    add_column :comments, :confirmed_at, :datetime
    add_reference :comments, :relayed_by_actor, index: false,
                                                foreign_key: { to_table: :actors, on_delete: :restrict }
    add_column :comments, :relay_activity_uri, :text
    add_index :comments, :relay_activity_uri
  end
end
