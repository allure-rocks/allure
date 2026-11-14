# frozen_string_literal: true

module AllureMcp
  module Tools
    # The account's workouts, newest first, with the web list's filters
    # (Workouts::ListQuery) and the REST API's encrypted cursors.
    class ListWorkouts < Base
      DEFAULT_LIMIT = 20
      MAX_LIMIT = 100
      CURSOR_CONTEXT = "mcp:list_workouts"

      tool_name "list_workouts"
      title "List workouts"
      description <<~TEXT.squish
        Lists the athlete's own workouts, newest first, as compact rows (id, sport, start, distance,
        times, ascent, average speed and pace, heart rate, power, places). Filter by sport slugs, a date
        range in the athlete's time zone, a place name, or text in the title and description. Pass the
        returned next_cursor to read further back. Use an id with get_workout_context.
      TEXT
      annotations(**READ_ONLY, title: "List workouts")
      input_schema(
        properties: {
          sport: { type: "string", description: "Comma-separated sport slugs, e.g. \"running,trail_running\"." },
          from: { type: "string", format: "date", description: "First day, YYYY-MM-DD, in the athlete's time zone." },
          to: { type: "string", format: "date", description: "Last day, YYYY-MM-DD, in the athlete's time zone." },
          place: { type: "string", maxLength: 120, description: "Part of a recorded place name." },
          query: { type: "string", maxLength: 120, description: "Text in the title or description." },
          commute: { type: "boolean", description: "true for commutes only, false to exclude them." },
          limit: { type: "integer", minimum: 1, maximum: MAX_LIMIT, description: "Rows to return (default #{DEFAULT_LIMIT})." },
          cursor: { type: "string", description: "next_cursor from a previous call." }
        },
        additionalProperties: false
      )

      class << self
        private

        def perform(context, sport: nil, from: nil, to: nil, place: nil, query: nil, commute: nil, limit: DEFAULT_LIMIT,
                    cursor: nil)
          user = context.user
          scope = filtered(user, sport:, from:, to:, place:, query:, commute:)
          if cursor.present?
            started_at, id = decode_cursor(cursor)
            scope = scope.where("workouts.started_at < :started_at OR (workouts.started_at = :started_at AND workouts.id < :id)",
                                started_at:, id:)
          end
          rows = scope.includes(:sport).reorder(started_at: :desc, id: :desc).limit(limit + 1).to_a
          more = rows.size > limit
          rows = rows.first(limit)
          {
            account: account(user),
            units: Base::UNITS,
            workouts: rows.map { summary(it, user) },
            next_cursor: (encode_cursor(rows.last) if more)
          }
        end

        def filtered(user, sport:, from:, to:, place:, query:, commute:)
          params = { q: query, place:, period: "all" }
          if from.present? || to.present?
            params.merge!(period: "custom", from: date(from, "from"), to: date(to, "to"))
          end
          params[:sports] = sport_ids(sport) if sport.present?
          params[:commute] = commute ? "commute" : "non_commute" unless commute.nil?
          Workouts::ListQuery.new(user:, params: ActionController::Parameters.new(params)).resolve
        end

        def sport_ids(value)
          slugs = value.to_s.split(",").map(&:strip).reject(&:empty?)
          sports = Sport.where(slug: slugs).pluck(:slug, :id).to_h
          unknown = slugs - sports.keys
          raise Base::InvalidArgument, "Unknown sport: #{unknown.join(', ')}." if unknown.any?

          sports.values.map(&:to_s)
        end

        def date(value, name)
          return if value.blank?

          Date.iso8601(value.to_s).iso8601
        rescue Date::Error
          raise Base::InvalidArgument, "#{name} must be a date written YYYY-MM-DD."
        end

        def encode_cursor(workout)
          Api::Rest::V1::Cursor.encode([ Api::Rest::V1::Cursor.dump(workout.started_at), workout.id ], context: CURSOR_CONTEXT)
        end

        def decode_cursor(cursor)
          value, id = Api::Rest::V1::Cursor.decode(cursor, context: CURSOR_CONTEXT)
          [ Time.iso8601(value.to_s), id ]
        rescue Api::Rest::V1::Cursor::Invalid, ArgumentError
          raise Base::InvalidArgument, "The cursor is not one this tool returned."
        end
      end
    end
  end
end
