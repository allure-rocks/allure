# frozen_string_literal: true

module AllureMcp
  module Tools
    # Everything Allure knows about one of the account's workouts, in one
    # answer (docs/dev/MCP.md): the owner's figures and data-quality findings,
    # laps and detected sections, splits, best and segment efforts, records,
    # equipment and the preceding weeks of training. Sections are switched
    # off by `include_*`; the track itself only at the token's location level.
    #
    # The owner-only sections are built by Workouts::ContextPayload, which the
    # assistant reads too; this tool adds what depends on the token.
    class GetWorkoutContext < Base
      tool_name "get_workout_context"
      title "Get workout context"
      description <<~TEXT.squish
        Returns the full context of one of the athlete's workouts for analysis: sport, start time (UTC and
        local), every recorded metric with average pace, device, places, owner notes, data-quality findings
        (faulty GPS, heart-rate or power readings and the plausible value of each contested figure),
        recorded laps, detected sections (climbs, descents, stops, pauses, loops, speed and power
        intervals), splits, best efforts over standard distances with personal places, segment efforts
        with leaderboard rank and the athlete's own history on each segment, records set, equipment, and
        the training of the four weeks before. Optionally adds a measurement series over distance and
        time, and the track geometry when the token allows it.
      TEXT
      annotations(**READ_ONLY, title: "Get workout context")
      input_schema(
        properties: {
          workout_id: { type: "string", description: "The workout id from list_workouts." },
          include_laps: { type: "boolean", description: "Recorded laps and detected sections (default true)." },
          include_splits: { type: "boolean", description: "Splits over split_distance (default true)." },
          split_distance: {
            type: "integer", minimum: 100, maximum: 100_000,
            description: "Split length in metres; default 1 km (500 m for rowing), longer for long workouts."
          },
          include_efforts: { type: "boolean", description: "Best efforts and segment efforts (default true)." },
          include_training: { type: "boolean", description: "The four weeks of training before (default true)." },
          include_series: { type: "boolean", description: "A measurement series over distance and time (default false)." },
          series_points: {
            type: "integer", minimum: 2, maximum: WorkoutSeries::MAX_POINTS,
            description: "Rows of the series (default 200)."
          },
          include_geometry: {
            type: "boolean",
            description: "The track coordinates, at the location level the token allows (default false)."
          },
          geometry_points: {
            type: "integer", minimum: 2, maximum: WorkoutGeometry::MAX_POINTS,
            description: "Coordinates to return at most (default #{WorkoutGeometry::DEFAULT_POINTS})."
          }
        },
        required: [ "workout_id" ],
        additionalProperties: false
      )

      class << self
        private

        def perform(context, workout_id:, include_laps: true, include_splits: true, split_distance: nil, include_efforts: true,
                    include_training: true, include_series: false, series_points: 200, include_geometry: false,
                    geometry_points: WorkoutGeometry::DEFAULT_POINTS)
          user = context.user
          workout = owned_workout(context, workout_id,
                                  includes: [ :sport, :import_connection, :active_publications, :scheduled_publications,
                                              { equipments: :equipment_type } ])
          level = context.token.effective_mcp_geometry
          body = Workouts::ContextPayload.new(workout, user:).call(
            include_laps:, include_splits:, split_distance:, include_efforts:, include_training:
          )
          body[:location_level] = level
          body[:series] = WorkoutSeries.new(workout, max_points: series_points).call if include_series
          body[:geometry] = WorkoutGeometry.new(workout, level:, max_points: geometry_points).call if include_geometry
          body
        end
      end
    end
  end
end
