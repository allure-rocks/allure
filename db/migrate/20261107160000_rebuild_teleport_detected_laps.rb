# frozen_string_literal: true

# A climb or a descent never spans a discontinuity (docs/dev/VIRTUAL-PLATFORMS.md): the
# smart-lap detector now breaks its elevation profile where the ground does not
# continue — a teleport, or a recording resumed elsewhere — so the jump is no
# longer counted as ascent. The phantom climb it produced held the
# biggest-climb record. The affected workouts are those whose two consecutive
# recording segments start 200 m or more apart, which is the detector's own
# threshold.
class RebuildTeleportDetectedLaps < ActiveRecord::Migration[8.1]
  # Solid Queue lives in another database. Let a failed enqueue leave the
  # migration unapplied so it can be retried; a rebuild is idempotent, so
  # re-enqueueing one is safe.
  disable_ddl_transaction!

  def up
    ids = select_values(<<~SQL)
      SELECT DISTINCT workouts.id
      FROM workouts
      JOIN track_segments AS previous ON previous.workout_id = workouts.id
      JOIN track_segments AS following
        ON following.workout_id = workouts.id AND following.position = previous.position + 1
      WHERE previous.geom IS NOT NULL AND following.geom IS NOT NULL
        AND ST_Distance(
          ST_EndPoint(previous.geom::geometry)::geography,
          ST_StartPoint(following.geom::geometry)::geography
        ) >= 200
      ORDER BY workouts.id
    SQL
    return if ids.empty?

    ids.each do |id|
      job = Laps::RebuildJob.perform_later(Workout.find(id))
      unless job && job.successfully_enqueued?
        raise ActiveRecord::MigrationError, "Could not enqueue the detected-lap rebuild; retry the migration."
      end
    end
  end

  def down
    # Derived-data reconciliation has no inverse: the rebuilt laps are the
    # current ones.
  end
end
