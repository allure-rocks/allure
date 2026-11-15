# frozen_string_literal: true

# The image theme of a received attachment. A route image is received in the
# light and the dark variant, advertised as two Image attachments distinguished
# by `allure:theme` (DESIGN.md §15.4, docs/dev/FEDERATION.md). GPX rows keep the
# default `light`, which is meaningless for them but keeps the unique
# descriptor key uniform.
class AddThemeToRemoteAttachments < ActiveRecord::Migration[8.1]
  def change
    add_column :remote_note_attachments, :theme, :string, default: "light", null: false
    add_check_constraint :remote_note_attachments,
                         "theme::text = ANY (ARRAY['light'::character varying::text, 'dark'::character varying::text])",
                         name: "remote_note_attachments_theme"
    remove_index :remote_note_attachments, name: "index_remote_note_attachments_on_remote_note_id_and_kind"
    add_index :remote_note_attachments, [ :remote_note_id, :kind, :theme ],
              unique: true,
              name: "index_remote_note_attachments_on_note_kind_and_theme"

    add_column :remote_segment_attachments, :theme, :string, default: "light", null: false
    add_check_constraint :remote_segment_attachments,
                         "theme::text = ANY (ARRAY['light'::character varying::text, 'dark'::character varying::text])",
                         name: "remote_segment_attachments_theme"
    remove_index :remote_segment_attachments, name: "index_remote_segment_attachments_on_remote_segment_id_and_kind"
    add_index :remote_segment_attachments, [ :remote_segment_id, :kind, :theme ],
              unique: true,
              name: "index_remote_segment_attachments_on_segment_kind_and_theme"
  end
end
