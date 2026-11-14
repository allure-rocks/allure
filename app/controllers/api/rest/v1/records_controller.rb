# frozen_string_literal: true

module Api
  module Rest
    module V1
      # The account's personal records (PLAN_API.md §6.2), as `/me/records`
      # lists them: the classic records per sport and type, and the
      # best-effort records per sport and standard distance.
      class RecordsController < BaseController
        require_scope "read"

        def index
          records = current_user.records.includes(:sport, :workout).order(:sport_id, :record_type)
          efforts = current_user.effort_records.includes(:sport, :workout).order(:sport_id, :distance_meters)
          render json: {
            records: records.map { record(it) },
            best_efforts: efforts.map { effort_record(it) }
          }
        end

        private

        def record(record)
          {
            sport: record.sport.slug,
            type: record.record_type,
            value: Formats.number(record.value),
            workout_id: record.workout&.to_param,
            achieved_at: Formats.time(record.workout_started_at)
          }
        end

        def effort_record(record)
          {
            sport: record.sport.slug,
            distance_key: record.distance_key,
            distance: Formats.number(record.distance_meters),
            elapsed_time: record.duration_seconds,
            workout_id: record.workout&.to_param,
            achieved_at: Formats.time(record.workout_started_at)
          }
        end
      end
    end
  end
end
