# frozen_string_literal: true

# Per-account track-display smoothing (PLAN_MAPLIBRE.md §9). `smooth_tracks`
# is the workout map's on/off toggle; `track_smoothing_level` is the intensity
# chosen in appearance settings. Course (segment) displays are always smoothed
# at the medium level and ignore these columns.
class AddTrackSmoothingToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :smooth_tracks, :boolean, default: false, null: false
    add_column :users, :track_smoothing_level, :string, default: "medium", null: false
    add_check_constraint :users,
                         "track_smoothing_level IN ('light', 'medium', 'strong')",
                         name: "users_track_smoothing_level"
  end
end
