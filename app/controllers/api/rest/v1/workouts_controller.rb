# frozen_string_literal: true

module Api
  module Rest
    module V1
      # The owner's workouts (docs/dev/API.md). Every lookup goes through the
      # token's account, so another account's workout is a 404, never a 403.
      class WorkoutsController < BaseController
        SORTS = {
          "-started_at" => [ :started_at, :desc ],
          "started_at" => [ :started_at, :asc ],
          "-distance" => [ :distance, :desc ],
          "distance" => [ :distance, :asc ],
          "-duration" => [ :duration, :desc ],
          "duration" => [ :duration, :asc ],
          "-ascent" => [ :ascent, :desc ],
          "ascent" => [ :ascent, :asc ]
        }.freeze
        BOOLEANS = { "true" => true, "false" => false }.freeze
        EDITABLE = %w[title description notes sport commute equipment_ids].freeze
        TEXT_FIELDS = %w[title description notes].freeze
        # The figures of a manual entry (docs/dev/MANUAL-ENTRY.md), named as the
        # representation names them, with the column each one writes. A
        # recording's figures are measured from its file and never written.
        MANUAL_FIELDS = {
          "started_at" => "started_at", "elapsed_time" => "duration", "moving_time" => "moving_time",
          "distance" => "distance", "ascent" => "ascent",
          "average_heart_rate" => "average_heart_rate", "max_heart_rate" => "max_heart_rate",
          "calories" => "calories", "average_power" => "average_power"
        }.freeze
        MANUAL_NUMBERS = %w[distance ascent].freeze
        MANUAL_REQUIRED = %w[sport started_at elapsed_time].freeze
        MANUAL_RENAMES = { duration: :elapsed_time, pause_time: :moving_time }.freeze
        ISO_OFFSET = /(Z|[+-]\d{2}:?\d{2})\z/
        SPLIT_DISTANCES = (100..100_000)
        DEFAULT_SPLIT_DISTANCE = 1_000

        require_scope "read", except: %i[create update destroy]
        require_scope "write", only: %i[create update destroy]
        idempotent only: :create

        def index
          sort = params[:sort].presence || "-started_at"
          column, direction = SORTS.fetch(sort) { raise InvalidParameter, "sort" }
          scope = filtered_scope.includes(:sport, :equipments)
          render json: paginate(scope, column:, direction:, context: "workouts:#{sort}") { serialize(it, detail: false) }
        end

        def show
          workout = owned_workout(includes: [ :sport, :equipments, :active_publications, :scheduled_publications, :weather ])
          return unless stale?(etag: [ workout, workout.equipments.map(&:id), workout.active_publications.map(&:status),
                                       workout.scheduled_publications.map(&:status), workout.weather&.updated_at ])

          render json: serialize(workout, detail: true)
        end

        def track
          workout = owned_workout(includes: :track_segments)
          return unless stale?(etag: [ workout, "track" ])

          render json: TrackSerializer.new(workout), content_type: "application/geo+json"
        end

        def original
          workout = owned_workout
          raise ActiveRecord::RecordNotFound unless workout.original_file.attached?

          fallback = Allure::ImportFormat.for_key(workout.import_format)&.content_type
          send_data workout.original_file.download,
                    filename: workout.original_file.filename.to_s,
                    type: workout.original_file.content_type || fallback,
                    disposition: "attachment"
        end

        # A manual entry (docs/dev/MANUAL-ENTRY.md): the web's « Saisie
        # manuelle » form, in SI units. Files go through /imports.
        def create
          body = request.request_parameters
          errors = unknown_fields(body, EDITABLE + MANUAL_FIELDS.keys)
          errors.concat((MANUAL_REQUIRED - body.keys).map { { field: it, code: "required", detail: "#{it} is required." } })
          attributes, sport, equipment_ids = edit_values(body, errors)
          attributes.merge!(manual_values(body, errors))
          return render_validation(errors) if errors.any?

          result = Workouts::ManualEntry.create(user: current_user, attributes: attributes.merge(sport:), equipment_ids:)
          return render_validation(field_errors(result.workout, rename: MANUAL_RENAMES)) unless result.success?

          response.headers["Location"] = api_url("/api/rest/v1/workouts/#{result.workout.to_param}")
          render json: serialize(reloaded(result.workout), detail: true), status: :created
        end

        # The web edit form's fields (docs/dev/API.md). Only the fields sent
        # change; a sport change re-analyses the workout from its original
        # file, exactly as the web does, and is all or nothing. A manual entry
        # also takes its figures.
        def update
          workout = owned_workout(includes: [ :sport, :equipments ])
          # A credit row is read-only except for its deletion (docs/dev/SHARED-ACTIVITIES.md).
          return render_problem(:unprocessable_content, "credited_workout") if workout.credit?
          return update_manual(workout) if workout.manual?

          body = request.request_parameters
          errors = unknown_fields(body, EDITABLE)
          attributes, sport, equipment_ids = edit_values(body, errors)
          return render_validation(errors) if errors.any?

          workout.assign_attributes(attributes)
          return render_validation(field_errors(workout)) unless workout.valid?

          changed = Webhooks::Events.changed_fields(workout.changes, TEXT_FIELDS + %w[commute])
          equipment_before = workout.equipment_ids.sort
          changed << "sport" if sport && sport.id != workout.sport_id
          if sport && sport.id != workout.sport_id
            begin
              Workouts::SportChange.new(workout:, sport:).call!
            rescue Workouts::SportChange::MissingOriginalFile, Workouts::SportChange::ReanalysisFailed
              return render_problem(:unprocessable_content, "sport_change_failed")
            end
          end
          workout.save!
          Equipments::Totals.sync(workout, equipment_ids) unless equipment_ids.nil?
          changed << "equipment_ids" if workout.reload.equipment_ids.sort != equipment_before
          Webhooks::Events.workout_updated(workout, changed)

          render json: serialize(reloaded(workout), detail: true)
        end

        # The web's deletion cascade: live publications are deleted and their
        # federated Delete sent, a scheduled one is cancelled.
        def destroy
          Workouts::WorkoutDeletion.new(user: current_user, workout: owned_workout).call!
          head :no_content
        end

        # Recorded laps, then every detected source (loops, route repeats,
        # pauses, climbs, descents, stops, intervals), each with its `source`.
        def laps
          workout = owned_workout
          recorded = workout.laps.order(:number).map { LapSerializers.recorded(it) }
          detected = workout.detected_laps.chronological.map { LapSerializers.detected(it) }
          render json: { data: recorded + detected }
        end

        def splits
          distance = split_distance
          workout = owned_workout(includes: [ :sport, :track_segments ])
          splits = Workouts::SplitsService.new(workout:, interval: distance).call
          render json: { distance:, data: splits.map { LapSerializers.split(it) } }
        end

        def best_efforts
          workout = owned_workout
          efforts = workout.best_efforts.includes(:sport).order(:distance_meters).to_a
          places = BestEfforts::PersonalPlaces.new(user: current_user, best_efforts: efforts).call
          render json: { data: efforts.map { LapSerializers.best_effort(it, places[it.id]) } }
        end

        def segment_efforts
          workout = owned_workout
          efforts = workout.segment_efforts.includes(:segment, :sport).order(:started_at, :segment_id, :occurrence_index).to_a
          places = Segments::PersonalPlaces.new(user: current_user, efforts:).call
          standings = Segments::Standings.new(segments: efforts.map(&:segment).uniq, viewer: current_user).call
                                         .index_by { [ it.segment.id, it.sport.id ] }
          render json: {
            data: efforts.map { LapSerializers.segment_effort(it, places[it.id], standings[[ it.segment_id, it.sport_id ]]) }
          }
        end

        private

        def update_manual(workout)
          body = request.request_parameters
          errors = unknown_fields(body, EDITABLE + MANUAL_FIELDS.keys)
          attributes, sport, equipment_ids = edit_values(body, errors)
          attributes.merge!(manual_values(body, errors))
          return render_validation(errors) if errors.any?

          attributes[:sport] = sport if sport
          result = Workouts::ManualEntry.new(workout:).call(attributes, equipment_ids:)
          return render_validation(field_errors(result.workout, rename: MANUAL_RENAMES)) unless result.success?

          render json: serialize(reloaded(workout), detail: true)
        end

        # A recording's figure is measured, never written: it is refused with
        # its own code rather than as an unknown field.
        def unknown_fields(body, accepted)
          (body.keys - accepted).map do |field|
            if MANUAL_FIELDS.key?(field)
              { field:, code: "not_editable", detail: "#{field} is measured from the recording and cannot be changed." }
            else
              { field:, code: "unknown", detail: "#{field} cannot be changed." }
            end
          end
        end

        # The sent figures of a manual entry, as columns, adding a field error
        # for each value of the wrong type. `null` clears an optional figure.
        def manual_values(body, errors)
          MANUAL_FIELDS.each_with_object({}) do |(field, column), values|
            next unless body.key?(field)

            value = body[field]
            if field == "started_at"
              time = iso_time(value)
              time ? values[column] = time : errors << { field:, code: "invalid_type", detail: "started_at must be an ISO 8601 time with an offset." }
            elsif value.nil? && !MANUAL_REQUIRED.include?(field)
              values[column] = nil
            elsif MANUAL_NUMBERS.include?(field) ? value.is_a?(Numeric) : value.is_a?(Integer)
              values[column] = value
            else
              kind = MANUAL_NUMBERS.include?(field) ? "a number" : "an integer"
              errors << { field:, code: "invalid_type", detail: "#{field} must be #{kind}." }
            end
          end
        end

        def iso_time(value)
          return unless value.is_a?(String) && value.match?(ISO_OFFSET)

          Time.iso8601(value).in_time_zone
        rescue ArgumentError
          nil
        end

        # Validates each sent field into [attributes, sport, equipment ids],
        # adding a field error for each refusal.
        def edit_values(body, errors)
          attributes = {}
          TEXT_FIELDS.each do |field|
            next unless body.key?(field)

            value = body[field]
            if value.nil? || value.is_a?(String)
              attributes[field] = value
            else
              errors << { field:, code: "invalid_type", detail: "#{field} must be a string or null." }
            end
          end
          if body.key?("commute")
            if [ true, false ].include?(body["commute"])
              attributes["commute"] = body["commute"]
            else
              errors << { field: "commute", code: "invalid_type", detail: "commute must be a boolean." }
            end
          end
          [ attributes, edited_sport(body, errors), edited_equipment_ids(body, errors) ]
        end

        def edited_sport(body, errors)
          return unless body.key?("sport")

          sport = Sport.find_by(slug: body["sport"].to_s, active: true) if body["sport"].is_a?(String)
          errors << { field: "sport", code: "unknown_sport", detail: "Unknown sport: #{body['sport'].inspect}." } unless sport
          sport
        end

        # The account's own equipment only; inactive equipment stays attached
        # when it already is and is not added otherwise, as on the web.
        def edited_equipment_ids(body, errors)
          return unless body.key?("equipment_ids")

          values = body["equipment_ids"]
          unless values.is_a?(Array) && values.all?(String)
            errors << { field: "equipment_ids", code: "invalid_type", detail: "equipment_ids must be an array of identifiers." }
            return
          end
          uuids = values.filter_map { decode_id(it) }
          owned = current_user.equipments.where(uuid: uuids).pluck(:uuid, :id).to_h
          unknown = values.reject { owned.key?(decode_id(it)) }
          if unknown.any?
            errors << { field: "equipment_ids", code: "unknown_equipment", detail: "Unknown equipment: #{unknown.join(', ')}." }
            return
          end
          uuids.map { owned.fetch(it) }.uniq
        end

        def decode_id(value)
          Allure::ShortId.decode(value)
        rescue ArgumentError
          nil
        end

        def reloaded(workout)
          current_user.workouts.includes(:sport, :equipments, :active_publications, :scheduled_publications).find(workout.id)
        end

        def split_distance
          return DEFAULT_SPLIT_DISTANCE if params[:distance].blank?

          value = Integer(params[:distance].to_s, 10)
          raise InvalidParameter, "distance" unless SPLIT_DISTANCES.cover?(value)

          value
        rescue ArgumentError
          raise InvalidParameter, "distance"
        end

        def serialize(workout, detail:) = WorkoutSerializer.new(workout, detail:).as_json

        def owned_workout(includes: nil)
          scope = current_user.workouts
          scope = scope.includes(includes) if includes
          scope.find_by!(uuid: Allure::ShortId.decode(params[:id]))
        rescue ArgumentError
          raise ActiveRecord::RecordNotFound
        end

        # The web list's filters (Workouts::ListQuery), named for the API.
        def filtered_scope
          query = { q: params[:q], place: params[:place], period: "all" }
          if params[:from].present? || params[:to].present?
            query[:period] = "custom"
            query[:from] = date_param(:from)
            query[:to] = date_param(:to)
          end
          query[:sports] = sport_ids if params[:sport].present?
          query[:commute] = { true => "commute", false => "non_commute" }.fetch(boolean_param(:commute)) unless params[:commute].nil?
          query[:publication] = boolean_param(:published) ? "published" : "not_published" unless params[:published].nil?
          scope = Workouts::ListQuery.new(user: current_user, params: ActionController::Parameters.new(query)).resolve
          equipment_filter(scope)
        end

        def sport_ids
          slugs = params[:sport].to_s.split(",").map(&:strip).reject(&:empty?)
          sports = Sport.where(slug: slugs).pluck(:slug, :id).to_h
          unknown = slugs - sports.keys
          raise InvalidParameter.new("sport", "Unknown sport: #{unknown.join(', ')}.") if unknown.any?

          sports.values.map(&:to_s)
        end

        def equipment_filter(scope)
          return scope if params[:equipment].blank?

          equipment = current_user.equipments.find_by(uuid: Allure::ShortId.decode(params[:equipment].to_s))
          raise InvalidParameter, "equipment" unless equipment

          scope.where(id: equipment.workouts.select(:id))
        rescue ArgumentError
          raise InvalidParameter, "equipment"
        end

        def date_param(name)
          return if params[name].blank?

          Date.iso8601(params[name].to_s).iso8601
        rescue Date::Error
          raise InvalidParameter, name.to_s
        end

        def boolean_param(name)
          BOOLEANS.fetch(params[name].to_s) { raise InvalidParameter, name.to_s }
        end
      end
    end
  end
end
