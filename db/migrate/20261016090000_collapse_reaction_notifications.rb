# frozen_string_literal: true

# PLAN_NOTIFICATIONS.md §8: reactions on one workout share one notification,
# whose subject becomes the workout. The existing per-reaction rows collapse
# into one row per (recipient, workout): unread when any of them was, dated
# by the newest, and recounted from the active reactions of accounts that
# still exist. Rows whose reaction or workout is gone are dropped.
class CollapseReactionNotifications < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      WITH grouped AS (
        SELECT n.user_id, r.workout_id,
               bool_or(n.read_at IS NULL) AS any_unread,
               max(n.read_at) AS last_read,
               max(n.created_at) AS last_at
        FROM notifications n
        JOIN reactions r ON r.id = n.subject_id
        JOIN workouts w ON w.id = r.workout_id AND w.user_id = n.user_id
        WHERE n.kind = 'reaction' AND n.subject_type = 'Reaction'
        GROUP BY n.user_id, r.workout_id
      ),
      counted AS (
        SELECT r.workout_id,
               count(*) AS total,
               (array_agg(r.actor_id ORDER BY r.created_at DESC, r.id DESC))[1] AS latest_actor_id
        FROM reactions r
        JOIN actors a ON a.id = r.actor_id AND a.tombstoned_at IS NULL
        WHERE r.undone_at IS NULL AND r.workout_id IS NOT NULL
        GROUP BY r.workout_id
      ),
      kinds AS (
        SELECT workout_id, jsonb_object_agg(kind, total) AS kinds
        FROM (
          SELECT r.workout_id, r.kind, count(*) AS total
          FROM reactions r
          JOIN actors a ON a.id = r.actor_id AND a.tombstoned_at IS NULL
          WHERE r.undone_at IS NULL AND r.workout_id IS NOT NULL
          GROUP BY r.workout_id, r.kind
        ) per_kind
        GROUP BY workout_id
      )
      INSERT INTO notifications (user_id, kind, subject_type, subject_id, actor_id, payload, read_at, created_at, updated_at)
      SELECT g.user_id, 'reaction', 'Workout', g.workout_id, c.latest_actor_id,
             jsonb_build_object('count', c.total, 'kinds', k.kinds),
             CASE WHEN g.any_unread THEN NULL ELSE g.last_read END,
             g.last_at, now()
      FROM grouped g
      JOIN counted c ON c.workout_id = g.workout_id
      JOIN kinds k ON k.workout_id = g.workout_id
      ON CONFLICT DO NOTHING
    SQL

    execute "DELETE FROM notifications WHERE kind = 'reaction' AND subject_type = 'Reaction'"
  end

  # The per-reaction rows are not rebuilt: a notification is a disposable
  # notice, and the next reaction starts a fresh one.
  def down
    execute "DELETE FROM notifications WHERE kind = 'reaction' AND subject_type = 'Workout'"
  end
end
