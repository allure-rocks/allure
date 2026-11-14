class AddDisplayNameToRegistrationInvitations < ActiveRecord::Migration[8.1]
  def change
    add_column :registration_invitations, :display_name, :string
    add_check_constraint :registration_invitations, "char_length(display_name) <= 60",
                         name: "registration_invitations_display_name_length"
  end
end
