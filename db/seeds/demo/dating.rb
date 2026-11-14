# frozen_string_literal: true

module DemoSeed
  # Re-dates the demo dataset near the present (PLAN_DEMO.md §2), for the demo
  # instance and the development seed alike: each family of recordings (the
  # files, the typed manual entries) is shifted by whole days so its newest
  # anchor lands on the end date, yesterday on a fresh database.
  #
  # A database that already holds the dataset keeps its dates: the end date is
  # read back from the shift its seeded recordings were imported with, so an
  # entry added to the manifest later lands beside them instead of drifting by
  # the days elapsed since the first run.
  class Dating
    SECONDS_PER_DAY = 86_400

    def self.near_present(anchors:, usernames:, today: Date.current)
      stored = Workout.recordings.joins(:user).where(users: { username: usernames }).order(:id).pick(:time_shift_seconds)
      end_date = stored ? anchors.fetch(:files) + stored.div(SECONDS_PER_DAY) : today - 1
      new(anchors:, end_date:)
    end

    # The files' own dates (DEMO_SEED_SHIFT=0).
    def self.none = new(anchors: {}, end_date: nil)

    def initialize(anchors:, end_date:)
      @anchors = anchors
      @end_date = end_date
    end

    def file_shift = shift_for(:files)
    def manual_shift = shift_for(:manual)

    private

    # Yesterday, never today: the model refuses a workout that starts in the
    # future, and the reset runs before some recordings' original time of day.
    def shift_for(family)
      return 0 unless @end_date

      [ (@end_date - @anchors.fetch(family)).to_i, 0 ].max * SECONDS_PER_DAY
    end
  end
end
