# frozen_string_literal: true

module Workouts
  # The synchronous bulk actions (PLAN_BULK_ACTIONS.md §3): the commute flag
  # and equipment links. Each call touches only the owner's rows, counts only
  # actual changes, and refreshes equipment totals once per equipment — never
  # per workout.
  class BulkQuickAction
    class InvalidAction < StandardError; end

    Result = Data.define(:action, :affected_count)

    ACTION = /\A(commute_on|commute_off|equipment_add|equipment_remove)(?::(\d+))?\z/

    def initialize(user:, workout_ids:, action:)
      @user = user
      @workout_ids = workout_ids
      @action = action.to_s
    end

    def call!
      match = ACTION.match(@action)
      raise InvalidAction unless match

      name, equipment_id = match.captures
      count = case name
      when "commute_on" then commute(true)
      when "commute_off" then commute(false)
      when "equipment_add" then equipment(equipment_id, add: true)
      when "equipment_remove" then equipment(equipment_id, add: false)
      end
      Result.new(action: name, affected_count: count)
    end

    private

    def commute(value)
      scope = @user.workouts.where(id: @workout_ids).where.not(commute: value)
      ids = scope.pluck(:id)
      count = scope.update_all(commute: value, updated_at: Time.current)
      announce(ids, "commute")
      count
    end

    # One `workout.updated` per workout changed (docs/dev/API.md).
    def announce(ids, field)
      @user.workouts.where(id: ids).find_each { Webhooks::Events.workout_updated(it, [ field ]) }
    end

    def equipment(equipment_id, add:)
      equipment = @user.equipments.find_by(id: equipment_id)
      raise InvalidAction unless equipment
      raise InvalidAction if add && !equipment.is_active?

      add ? attach(equipment) : detach(equipment)
    end

    def attach(equipment)
      existing = WorkoutEquipment.where(equipment_id: equipment.id, workout_id: @workout_ids).pluck(:workout_id)
      new_ids = @workout_ids - existing
      return 0 if new_ids.empty?

      WorkoutEquipment.insert_all(new_ids.map { |workout_id| { workout_id:, equipment_id: equipment.id } })
      Equipments::Totals.refresh(equipment)
      announce(new_ids, "equipment_ids")
      new_ids.length
    end

    def detach(equipment)
      links = WorkoutEquipment.where(equipment_id: equipment.id, workout_id: @workout_ids)
      ids = links.pluck(:workout_id)
      count = links.delete_all
      Equipments::Totals.refresh(equipment) if count.positive?
      announce(ids, "equipment_ids")
      count
    end
  end
end
