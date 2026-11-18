# frozen_string_literal: true

module Workouts
  # The owner-only context of one workout (docs/dev/MCP.md §5.1, AI.md §3.1):
  # every figure Allure derives from it, its equipment and record set, its laps,
  # splits and efforts, and the four weeks before. Built from the REST
  # serializers and the services the web uses, so a metric has one
  # implementation.
  #
  # `AllureMcp::Tools::GetWorkoutContext` adds the token's location level, the
  # optional measurement series and the optional geometry; the assistant reads
  # the same object, geometry off, to compute its facts.
  #
  # The caller loads the workout with its owner (`user:`) and the associations
  # the sections read; this object never checks ownership.
  class ContextPayload
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
    DETECTED_LAPS_PER_SOURCE = 50
    MAX_SPLITS = 60
    TRAINING_WINDOW = 28.days
    RECENT_SAME_SPORT = 5

    class << self
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

    attr_reader :workout, :user

    def initialize(workout, user:)
      @workout = workout
      @user = user
    end

    def call(include_laps: true, include_splits: true, split_distance: nil, include_efforts: true,
             include_training: true)
      body = {
        account: self.class.account(user),
        units: UNITS,
        workout: workout_section,
        equipment: workout.equipments.map { Api::Rest::V1::CatalogSerializers.equipment(it) },
        records_set: records_set
      }
      body[:laps] = laps if include_laps
      body[:splits] = splits(split_distance) if include_splits
      if include_efforts
        body[:best_efforts] = best_efforts
        body[:segment_efforts] = segment_efforts
      end
      body[:training] = training if include_training
      body
    end

    private

    def workout_section
      serialized = Api::Rest::V1::WorkoutSerializer.new(workout, detail: true).as_json
      links = serialized.delete(:links)
      sport = workout.sport
      serialized.merge(
        web_url: links[:web],
        local_start: local_time(workout.started_at),
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

    # The records this workout holds today: classic records (value in the SI
    # unit of `metric`; a pace is seconds per kilometre) and best-effort
    # records per standard distance.
    def records_set
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

    def laps
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

    def splits(requested)
      distance = requested || automatic_split_distance
      rows = Workouts::SplitsService.new(workout:, interval: distance).call
      {
        distance:,
        rows: rows.first(MAX_SPLITS).map { Api::Rest::V1::LapSerializers.split(it).compact },
        truncated: rows.size > MAX_SPLITS
      }
    end

    def automatic_split_distance
      distance = workout.sport.pace_basis_metres || 1_000
      distance *= 5 while workout.distance.to_f / distance > MAX_SPLITS
      distance
    end

    def best_efforts
      efforts = workout.best_efforts.includes(:sport).order(:distance_meters).to_a
      places = BestEfforts::PersonalPlaces.new(user:, best_efforts: efforts).call
      efforts.map { Api::Rest::V1::LapSerializers.best_effort(it, places[it.id]) }
    end

    def segment_efforts
      efforts = workout.segment_efforts.includes(:segment, :sport).order(:started_at, :segment_id, :occurrence_index).to_a
      return [] if efforts.empty?

      places = Segments::PersonalPlaces.new(user:, efforts:).call
      standings = Segments::Standings.new(segments: efforts.map(&:segment).uniq, viewer: user).call
                                         .index_by { [ it.segment.id, it.sport.id ] }
      history = own_history(efforts)
      efforts.map do |effort|
        Api::Rest::V1::LapSerializers.segment_effort(effort, places[effort.id], standings[[ effort.segment_id, effort.sport_id ]])
          .except(:id)
          .merge(own_history: history_for(effort, history[[ effort.segment_id, effort.sport_id ]]))
      end
    end

    # Every own effort on the same (segment, sport), oldest first.
    def own_history(efforts)
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

    # The four weeks before this workout: totals for its sport and for every
    # sport, and the last few workouts of the same sport.
    def training
      window = (workout.started_at - TRAINING_WINDOW)...workout.started_at
      before = user.workouts.where(started_at: window)
      same_sport = before.where(sport_id: workout.sport_id)
      {
        window_days: TRAINING_WINDOW.in_days.to_i,
        same_sport: totals(same_sport),
        all_sports: totals(before),
        recent_same_sport: user.workouts.where(sport_id: workout.sport_id).where(started_at: ...workout.started_at)
                               .includes(:sport).newest_first.limit(RECENT_SAME_SPORT).map { summary(it) }
      }
    end

    def totals(scope)
      count, distance, moving, elapsed, ascent = scope.pick(
        Arel.sql("COUNT(*)"), Arel.sql("COALESCE(SUM(distance), 0)"), Arel.sql("COALESCE(SUM(moving_time), 0)"),
        Arel.sql("COALESCE(SUM(duration), 0)"), Arel.sql("COALESCE(SUM(ascent), 0)")
      )
      { workouts: count, distance: number(distance), moving_time: moving.to_i, elapsed_time: elapsed.to_i, ascent: number(ascent) }
    end

    # The class methods shared with the other tools, with this workout's owner.
    def local_time(value) = self.class.local_time(user, value)
    def pace(speed, sport) = self.class.pace(speed, sport)
    def number(value) = self.class.number(value)
    def time(value) = self.class.time(value)
    def summary(other) = self.class.summary(other, user)
  end
end
