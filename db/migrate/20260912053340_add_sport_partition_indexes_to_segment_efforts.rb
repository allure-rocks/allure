class AddSportPartitionIndexesToSegmentEfforts < ActiveRecord::Migration[8.1]
  def change
    remove_index :segment_efforts, name: "index_segment_efforts_on_segment_id_and_user_id"

    # A multi-sport segment carries one personal best per athlete and sport.
    add_index :segment_efforts, [ :segment_id, :user_id, :sport_id ],
              name: "index_segment_efforts_on_segment_user_sport_personal_best",
              where: "personal_best"

    # Per-sport leaderboard ordering.
    add_index :segment_efforts, [ :segment_id, :sport_id, :elapsed_time ],
              name: "index_segment_efforts_on_segment_sport_elapsed_time"
  end
end
