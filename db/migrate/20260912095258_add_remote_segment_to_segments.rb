class AddRemoteSegmentToSegments < ActiveRecord::Migration[8.1]
  def change
    add_column :segments, :remote_segment_id, :bigint

    add_foreign_key :segments, :remote_segments, on_delete: :nullify
    add_index :segments, [ :remote_segment_id, :user_id ],
              unique: true,
              where: "remote_segment_id IS NOT NULL",
              name: "index_segments_on_remote_segment_id_and_user_id"
  end
end
