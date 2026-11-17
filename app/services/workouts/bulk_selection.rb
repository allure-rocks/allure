# frozen_string_literal: true

module Workouts
  # Resolves the owner's bulk selection (PLAN_BULK_ACTIONS.md §2): either the
  # filter scope of the list the owner is looking at, replayed through the
  # shared ListQuery, or explicit workout short ids. Foreign and malformed
  # identifiers are dropped without a hint, the cap is enforced before any
  # write, and the returned order is the list's own (filter scope) or the
  # submitted order (explicit ids).
  class BulkSelection
    MAX_WORKOUTS = 500

    class TooManyWorkouts < StandardError; end

    def initialize(user:, params:)
      @user = user
      @params = params
    end

    def ids
      filter_scope? ? filter_scope_ids : explicit_ids
    end

    private

    def filter_scope? = @params[:scope].to_s == "filter"

    def filter_scope_ids
      # A credit row is never selectable: it is removed one by one
      # (docs/dev/SHARED-ACTIVITIES.md).
      scope = ListQuery.new(user: @user, params: @params).resolve(scope: @user.workouts.authored)
      raise TooManyWorkouts if scope.count > MAX_WORKOUTS

      scope.pluck(:id)
    end

    def explicit_ids
      uuids = Array(@params[:workout_ids]).map(&:to_s).uniq.filter_map { |value| decode(value) }
      raise TooManyWorkouts if uuids.length > MAX_WORKOUTS

      by_uuid = @user.workouts.authored.where(uuid: uuids).pluck(:uuid, :id).to_h
      uuids.filter_map { |uuid| by_uuid[uuid] }
    end

    def decode(value)
      Allure::ShortId.decode(value)
    rescue ArgumentError
      nil
    end
  end
end
