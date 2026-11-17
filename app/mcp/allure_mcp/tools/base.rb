# frozen_string_literal: true

module AllureMcp
  module Tools
    # What every Allure tool shares (docs/dev/MCP.md): the token's account as
    # the only scope, owner lookups that answer "not found" for anything else,
    # compact JSON text answers, and the outcome reported to the metrics.
    class Base < MCP::Tool
      class NotFound < StandardError; end
      class InvalidArgument < StandardError; end

      FLOAT_DECIMALS = 5
      READ_ONLY = { read_only_hint: true, destructive_hint: false, idempotent_hint: true, open_world_hint: false }.freeze

      UNITS = {
        distance: "m",
        elevation: "m",
        ascent: "m",
        time: "s",
        speed: "m/s",
        pace: "s per pace_basis_metres",
        grade: "%",
        grade_adjusted_pace: "s/km",
        heart_rate: "bpm",
        cadence: "per minute (revolutions, strokes or steps, as the device records)",
        power: "W",
        calories: "kcal",
        timestamps: "RFC 3339, UTC"
      }.freeze

      class << self
        def call(server_context:, **arguments)
          payload = rounded(perform(server_context, **arguments))
          server_context.outcome = "ok"
          MCP::Tool::Response.new([ { type: "text", text: JSON.generate(payload) } ])
        rescue NotFound => error
          failure(server_context, "not_found", error.message)
        rescue InvalidArgument => error
          failure(server_context, "invalid", error.message)
        end

        private

        def perform(_context, **)
          raise NotImplementedError
        end

        # Float noise such as 262.2999999999993 costs a model tokens and
        # nothing else; five decimals keep a coordinate within a metre.
        def rounded(value)
          case value
          when Float then value.round(FLOAT_DECIMALS)
          when Hash then value.transform_values { rounded(it) }
          when Array then value.map { rounded(it) }
          else value
          end
        end

        def failure(context, outcome, message)
          context.outcome = outcome
          MCP::Tool::Response.new([ { type: "text", text: message } ], error: true)
        end

        def owned_workout(context, id, includes: nil)
          uuid = Allure::ShortId.decode(id.to_s)
          scope = context.user.workouts
          scope = scope.includes(includes) if includes
          scope.find_by(uuid:) || raise(NotFound, missing_workout(id))
        rescue ArgumentError
          raise NotFound, missing_workout(id)
        end

        def missing_workout(id) = "No workout #{id.to_s.truncate(40).inspect} on this account. Use list_workouts to find an id."

        def account(user)
          { unit_system: user.unit_system, time_zone: user.time_zone, week_start: user.week_start }
        end

        def local_time(user, time)
          zone = Time.find_zone(user.time_zone) || Time.zone
          time&.in_time_zone(zone)&.iso8601
        end

        def number(value) = Api::Rest::V1::Formats.number(value)
        def time(value) = Api::Rest::V1::Formats.time(value)

        # Seconds per pace basis (1 km, or 500 m for rowing), from a speed.
        def pace(speed, sport)
          speed = speed.to_f
          return unless speed.positive?

          ((sport.pace_basis_metres || 1_000) / speed).round
        end

        # The compact row of list_workouts and the training context.
        def summary(workout, user)
          {
            id: workout.to_param,
            title: workout.title,
            sport: workout.sport.slug,
            commute: workout.commute,
            started_at: time(workout.started_at),
            local_start: local_time(user, workout.started_at),
            distance: number(workout.distance),
            elapsed_time: workout.duration,
            moving_time: workout.moving_time,
            ascent: number(workout.ascent),
            average_speed: number(workout.average_speed),
            average_pace: pace(workout.average_speed, workout.sport),
            average_heart_rate: workout.average_heart_rate,
            average_power: workout.average_power,
            places: Array(workout.places).filter_map { it["name"] if it.is_a?(Hash) },
            # `credit`: another account recorded it; metrics only, no track
            # (docs/dev/SHARED-ACTIVITIES.md). `manual`: typed in by hand, no track
            # and no sensor series (docs/dev/MANUAL-ENTRY.md).
            origin: workout.origin
          }
        end
      end
    end
  end
end
