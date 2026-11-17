# frozen_string_literal: true

module Workouts
  # Creates and edits a manual entry (PLAN_MANUAL_ENTRY.md): a workout its
  # owner typed in, with no file, no geometry and nothing derived from a track.
  # The figures arrive in SI, as persisted; the web form and the REST API each
  # convert their own input first. What a recording's analysis would derive
  # from those figures (the pause time, the average speed and pace) is derived
  # here, and nothing else: no best effort, no lap, no segment, no image, no
  # place, no detection and no automatic publication ever follows.
  class ManualEntry
    MEASURED = %w[
      started_at duration moving_time distance ascent
      average_heart_rate max_heart_rate calories average_power
    ].freeze
    TEXT = %w[title description notes].freeze
    FIELDS = (MEASURED + TEXT + %w[sport commute]).freeze
    # The names a change is announced under, as the REST representation spells
    # them (docs/dev/API.md).
    CHANGE_NAMES = { "duration" => "elapsed_time", "sport_id" => "sport" }.freeze

    Result = Data.define(:workout, :changed) do
      def success? = workout.persisted? && workout.errors.empty?
    end

    def self.create(user:, attributes:, equipment_ids: nil)
      new(workout: user.workouts.build(origin: "manual")).call(attributes, equipment_ids:)
    end

    def initialize(workout:)
      raise ArgumentError, "not a manual entry" unless workout.manual?

      @workout = workout
    end

    # Only the given fields change. `equipment_ids: nil` leaves the equipment
    # as it is, `[]` clears it (Equipments::Totals.sync).
    def call(attributes, equipment_ids: nil)
      creating = @workout.new_record?
      equipment_before = creating ? [] : @workout.equipment_ids.sort
      @workout.assign_attributes(attributes.to_h.stringify_keys.slice(*FIELDS))
      derive
      return Result.new(workout: @workout, changed: []) unless @workout.save

      changed = creating ? [] : changed_fields
      # After the save has committed: the model's own callback moves the
      # totals of the equipment already attached, the sync then adds and
      # removes links at the new figures.
      Equipments::Totals.sync(@workout, equipment_ids)
      changed << "equipment_ids" if !creating && @workout.reload.equipment_ids.sort != equipment_before
      if creating
        Webhooks::Events.workout_created(@workout)
      else
        Webhooks::Events.workout_updated(@workout, changed)
      end
      Result.new(workout: @workout, changed:)
    end

    private

    # Distance and ascent are zero when not given: the columns are mandatory
    # and the page reads a zero as « not entered ». The moving time is the
    # whole duration unless the owner said otherwise, and follows a changed
    # duration while it still was the whole of it.
    def derive
      @workout.distance ||= 0
      @workout.ascent ||= 0
      @workout.descent ||= 0
      @workout.moving_time ||= @workout.duration
      if @workout.persisted? && @workout.duration_changed? && !@workout.moving_time_changed? &&
         @workout.moving_time == @workout.duration_was
        @workout.moving_time = @workout.duration
      end
      @workout.pause_time = @workout.duration - @workout.moving_time if @workout.duration && @workout.moving_time
      moving = @workout.moving_time.to_i
      speed = moving.positive? ? @workout.distance.to_f / moving : 0.0
      @workout.average_speed = speed.round(4)
      @workout.average_pace = speed.positive? ? (1000.0 / speed).round : nil
    end

    def changed_fields
      fields = @workout.saved_changes.keys.map { CHANGE_NAMES.fetch(it, it) }
      named = Webhooks::Events.changed_fields(@workout.saved_changes, TEXT)
      (fields & (MEASURED.map { CHANGE_NAMES.fetch(it, it) } + %w[sport commute])) + named
    end
  end
end
