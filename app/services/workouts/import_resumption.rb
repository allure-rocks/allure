# frozen_string_literal: true

module Workouts
  # A batch job interrupted after the importer committed a workout but before
  # its entry was finished (a deploy, a restart) runs again and meets that
  # workout as a duplicate of the very entry that created it. The entry claims
  # it back when it was already `processing` before this run, the workout was
  # created after the entry started, and no other entry holds it; it is then
  # imported, not a duplicate of itself (docs/dev/STRAVA-ARCHIVE.md).
  module ImportResumption
    module_function

    def claims?(entry:, workout:, resumed:)
      return false unless resumed && workout && entry.started_at
      return false if workout.created_at < entry.started_at

      !WorkoutImportEntry.where(workout_id: workout.id).where.not(id: entry.id).exists?
    end
  end
end
