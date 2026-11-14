# frozen_string_literal: true

module Equipments
  # Maintains the denormalized lifetime totals on `Equipment` rows. All
  # amounts are SI (metres, seconds, count), matching the workout columns
  # they sum. `total_duration` is defined as moving time, not elapsed.
  module Totals
    module_function

    # Replaces a workout's equipment links with the given IDs, updating join
    # rows and totals atomically. `nil` leaves links untouched; `[]` clears
    # them. Only the workout owner's equipment is considered (foreign IDs are
    # silently ignored, never an existence leak); inactive equipment is never
    # newly attached, but already-attached inactive rows persist while still
    # submitted.
    def sync(workout, equipment_ids)
      return if equipment_ids.nil?

      submitted = Array(equipment_ids).map(&:to_i).uniq
      owned = workout.user.equipments.where(id: submitted).index_by(&:id)
      current = workout.equipment_ids

      added = submitted.select { |id| owned[id]&.is_active? } - current
      removed = current - submitted
      kept = current - removed

      Equipment.transaction do
        removed.each { |id| decrement(Equipment.find(id), workout) }
        added.each { |id| increment(Equipment.find(id), workout) }
        workout.equipment_ids = kept + added
      end
    end

    def increment(equipment, workout)
      equipment.reload
      equipment.update!(
        total_distance: equipment.total_distance + workout.distance,
        total_duration: equipment.total_duration + workout.moving_time,
        total_moving: equipment.total_moving + workout.moving_time,
        total_workouts: equipment.total_workouts + 1
      )
    end

    def decrement(equipment, workout)
      equipment.reload
      # Clamped at zero so stale totals (from a missed diff) fail safe
      # instead of violating the non-negative check; `refresh` repairs drift.
      equipment.update!(
        total_distance: [ equipment.total_distance - workout.distance, 0 ].max,
        total_duration: [ equipment.total_duration - workout.moving_time, 0 ].max,
        total_moving: [ equipment.total_moving - workout.moving_time, 0 ].max,
        total_workouts: [ equipment.total_workouts - 1, 0 ].max
      )
    end

    def diff(equipment, old_distance:, old_moving:, new_distance:, new_moving:)
      equipment.reload
      equipment.update!(
        total_distance: [ equipment.total_distance - old_distance + new_distance, 0 ].max,
        total_duration: [ equipment.total_duration - old_moving + new_moving, 0 ].max,
        total_moving: [ equipment.total_moving - old_moving + new_moving, 0 ].max
      )
    end

    # Recomputes all four totals from the attached workouts, repairing any
    # drift from missed increments, diffs, or direct deletes.
    def refresh(equipment)
      count, distance_sum, moving_sum = equipment.workouts.pick(
        Arel.sql("COUNT(*)"),
        Arel.sql("COALESCE(SUM(distance), 0)"),
        Arel.sql("COALESCE(SUM(moving_time), 0)")
      )
      equipment.update_columns(
        total_workouts: count,
        total_distance: distance_sum,
        total_duration: moving_sum,
        total_moving: moving_sum
      )
    end
  end
end
