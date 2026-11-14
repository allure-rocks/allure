class AddAudienceToRemoteNotes < ActiveRecord::Migration[8.1]
  def change
    add_column :remote_notes, :audience, :string, null: false, default: "public"
    add_check_constraint :remote_notes,
                         "audience IN ('public', 'followers')",
                         name: "remote_notes_audience"
  end
end
