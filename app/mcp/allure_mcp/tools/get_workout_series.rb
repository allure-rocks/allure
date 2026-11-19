# frozen_string_literal: true

module AllureMcp
  module Tools
    # One workout's measurements over a distance or time range, at a chosen
    # resolution: the zoom behind get_workout_context's overview.
    class GetWorkoutSeries < Base
      tool_name "get_workout_series"
      title "Get workout series"
      description <<~TEXT.squish
        Returns one workout's recorded measurements (elevation, speed, heart rate, cadence, power) as a
        table over cumulative distance and elapsed time, never a GPS coordinate. Narrow it to a distance
        range (metres from the start) or a time range (seconds from the start) to study an interval, a
        climb or a lap from get_workout_context in detail. Extremes and recording gaps are always kept when
        the range is thinned to max_points. Speed is in m/s.
      TEXT
      annotations(**READ_ONLY, title: "Get workout series")
      input_schema(
        properties: {
          workout_id: { type: "string", description: "The workout id from list_workouts." },
          series: {
            type: "array", uniqueItems: true,
            items: { type: "string", enum: WorkoutSeries::SERIES.map(&:to_s) },
            description: "Measurements to include; default every one recorded."
          },
          from_distance: { type: "number", minimum: 0, description: "Start of the range, metres from the start." },
          to_distance: { type: "number", minimum: 0, description: "End of the range, metres from the start." },
          from_time: { type: "number", minimum: 0, description: "Start of the range, seconds from the start." },
          to_time: { type: "number", minimum: 0, description: "End of the range, seconds from the start." },
          max_points: {
            type: "integer", minimum: 2, maximum: WorkoutSeries::MAX_POINTS,
            description: "Rows to return at most (default #{WorkoutSeries::DEFAULT_POINTS})."
          }
        },
        required: [ "workout_id" ],
        additionalProperties: false
      )

      class << self
        private

        def perform(context, workout_id:, series: nil, from_distance: nil, to_distance: nil, from_time: nil, to_time: nil,
                    max_points: WorkoutSeries::DEFAULT_POINTS)
          check_range(from_distance, to_distance, "distance")
          check_range(from_time, to_time, "time")
          workout = owned_workout(context, workout_id, includes: %i[sport track_segments])
          {
            workout_id: workout.to_param,
            sport: workout.sport.slug,
            units: Workouts::ContextPayload::UNITS,
            series: WorkoutSeries.new(workout, series:, from_distance:, to_distance:, from_time:, to_time:,
                                               max_points:).call
          }
        end

        def check_range(from, to, name)
          return unless from && to && from > to

          raise Base::InvalidArgument, "from_#{name} must not be after to_#{name}."
        end
      end
    end
  end
end
