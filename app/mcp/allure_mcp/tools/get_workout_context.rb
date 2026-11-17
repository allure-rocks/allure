# frozen_string_literal: true

module AllureMcp
  module Tools
    # Everything Allure knows about one of the account's workouts, in one
    # answer (docs/dev/MCP.md): the owner's figures and data-quality findings,
    # laps and detected sections, splits, best and segment efforts, records,
    # equipment and the preceding weeks of training. Sections are switched
    # off by `include_*`; the track itself only at the token's location level.
    class GetWorkoutContext < Base
      DETECTED_LAPS_PER_SOURCE = 50
      MAX_SPLITS = 60
      TRAINING_WINDOW = 28.days
      RECENT_SAME_SPORT = 5

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
          body = {
            account: account(user),
            units: Base::UNITS,
            location_level: level,
            workout: workout_section(workout, user),
            equipment: workout.equipments.map { Api::Rest::V1::CatalogSerializers.equipment(it) },
            records_set: records_set(workout)
          }
          body[:laps] = laps(workout) if include_laps
          body[:splits] = splits(workout, split_distance) if include_splits
          if include_efforts
            body[:best_efforts] = best_efforts(workout, user)
            body[:segment_efforts] = segment_efforts(workout, user)
          end
          body[:training] = training(workout, user) if include_training
          body[:series] = WorkoutSeries.new(workout, max_points: series_points).call if include_series
          body[:geometry] = WorkoutGeometry.new(workout, level:, max_points: geometry_points).call if include_geometry
          body
        end

        def workout_section(workout, user)
          serialized = Api::Rest::V1::WorkoutSerializer.new(workout, detail: true).as_json
          links = serialized.delete(:links)
          sport = workout.sport
          serialized.merge(
            web_url: links[:web],
            local_start: local_time(user, workout.started_at),
            sport_details: {
              slug: sport.slug,
              name: I18n.t("sports.#{sport.slug}", locale: :en, default: sport.label),
              family: sport.colour_group,
              virtual: sport.virtual,
              pace_basis_metres: sport.pace_basis_metres || 1_000
            },
            average_pace: pace(workout.average_speed, sport),
            elevation_filter: workout.elevation_filter
          )
        end

        # The records this workout holds today: classic records (value in the
        # SI unit of `metric`; a pace is seconds per kilometre) and best-effort
        # records per standard distance.
        def records_set(workout)
          classic = workout.records.includes(:sport).order(:record_type).map do |record|
            { sport: record.sport.slug, type: record.record_type, metric: Record::METRIC_KEYS[record.record_type],
              value: number(record.value) }
          end
          efforts = workout.effort_records.includes(:sport).order(:distance_meters).map do |record|
            { sport: record.sport.slug, distance_key: record.distance_key, distance: number(record.distance_meters),
              elapsed_time: record.duration_seconds }
          end
          { records: classic, best_effort_records: efforts }
        end

        def laps(workout)
          recorded = workout.laps.order(:number).map { Api::Rest::V1::LapSerializers.recorded(it).compact }
          detected = workout.detected_laps.chronological.to_a.group_by(&:source)
          truncated = detected.select { |_source, rows| rows.size > DETECTED_LAPS_PER_SOURCE }.keys
          {
            recorded:,
            detected: detected.transform_values do |rows|
              rows.first(DETECTED_LAPS_PER_SOURCE).map { Api::Rest::V1::LapSerializers.detected(it).except(:source).compact }
            end,
            truncated_sources: truncated
          }
        end

        def splits(workout, requested)
          distance = requested || automatic_split_distance(workout)
          rows = Workouts::SplitsService.new(workout:, interval: distance).call
          {
            distance:,
            rows: rows.first(MAX_SPLITS).map { Api::Rest::V1::LapSerializers.split(it).compact },
            truncated: rows.size > MAX_SPLITS
          }
        end

        def automatic_split_distance(workout)
          distance = workout.sport.pace_basis_metres || 1_000
          distance *= 5 while workout.distance.to_f / distance > MAX_SPLITS
          distance
        end

        def best_efforts(workout, user)
          efforts = workout.best_efforts.includes(:sport).order(:distance_meters).to_a
          places = BestEfforts::PersonalPlaces.new(user:, best_efforts: efforts).call
          efforts.map { Api::Rest::V1::LapSerializers.best_effort(it, places[it.id]) }
        end

        def segment_efforts(workout, user)
          efforts = workout.segment_efforts.includes(:segment, :sport).order(:started_at, :segment_id, :occurrence_index).to_a
          return [] if efforts.empty?

          places = Segments::PersonalPlaces.new(user:, efforts:).call
          standings = Segments::Standings.new(segments: efforts.map(&:segment).uniq, viewer: user).call
                                         .index_by { [ it.segment.id, it.sport.id ] }
          history = own_history(efforts, user)
          efforts.map do |effort|
            Api::Rest::V1::LapSerializers.segment_effort(effort, places[effort.id], standings[[ effort.segment_id, effort.sport_id ]])
              .except(:id)
              .merge(own_history: history_for(effort, history[[ effort.segment_id, effort.sport_id ]]))
          end
        end

        # Every own effort on the same (segment, sport), oldest first.
        def own_history(efforts, user)
          user.segment_efforts
              .where(segment_id: efforts.map(&:segment_id).uniq, sport_id: efforts.map(&:sport_id).uniq)
              .order(:started_at, :id)
              .pluck(:segment_id, :sport_id, :id, :elapsed_time, :started_at)
              .group_by { [ it[0], it[1] ] }
        end

        def history_for(effort, rows)
          rows = Array(rows)
          times = rows.map { it[3] }.sort
          previous = rows.select { it[4] < effort.started_at }.last
          {
            attempts: rows.size,
            best_time: times.first,
            median_time: times.empty? ? nil : times[times.size / 2],
            rank_among_own: (times.index { it >= effort.elapsed_time } || times.size) + 1,
            previous_attempt: previous && { elapsed_time: previous[3], started_at: time(previous[4]) }
          }
        end

        # The four weeks before this workout: totals for its sport and for
        # every sport, and the last few workouts of the same sport.
        def training(workout, user)
          window = (workout.started_at - TRAINING_WINDOW)...workout.started_at
          before = user.workouts.where(started_at: window)
          same_sport = before.where(sport_id: workout.sport_id)
          {
            window_days: TRAINING_WINDOW.in_days.to_i,
            same_sport: totals(same_sport),
            all_sports: totals(before),
            recent_same_sport: user.workouts.where(sport_id: workout.sport_id).where(started_at: ...workout.started_at)
                                   .includes(:sport).newest_first.limit(RECENT_SAME_SPORT).map { summary(it, user) }
          }
        end

        def totals(scope)
          count, distance, moving, elapsed, ascent = scope.pick(
            Arel.sql("COUNT(*)"), Arel.sql("COALESCE(SUM(distance), 0)"), Arel.sql("COALESCE(SUM(moving_time), 0)"),
            Arel.sql("COALESCE(SUM(duration), 0)"), Arel.sql("COALESCE(SUM(ascent), 0)")
          )
          { workouts: count, distance: number(distance), moving_time: moving.to_i, elapsed_time: elapsed.to_i, ascent: number(ascent) }
        end
      end
    end
  end
end
