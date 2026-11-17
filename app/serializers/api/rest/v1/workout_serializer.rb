# frozen_string_literal: true

module Api
  module Rest
    module V1
      # The owner's Workout representation (docs/dev/API.md). SI units as
      # persisted; nullable measurements stay null when not recorded. The list
      # form omits the free text and the owner-only analysis detail.
      class WorkoutSerializer
        def initialize(workout, detail:)
          @workout = workout
          @detail = detail
        end

        def as_json(*)
          workout = @workout
          body = {
            id: workout.to_param,
            title: workout.title,
            sport: workout.sport.slug,
            commute: workout.commute,
            started_at: Formats.time(workout.started_at),
            ended_at: Formats.time(workout.started_at + workout.duration),
            elapsed_time: workout.duration,
            moving_time: workout.moving_time,
            pause_time: workout.pause_time,
            distance: Formats.number(workout.distance),
            ascent: Formats.number(workout.ascent),
            descent: Formats.number(workout.descent),
            min_elevation: Formats.number(workout.min_elevation),
            max_elevation: Formats.number(workout.max_elevation),
            average_speed: Formats.number(workout.average_speed),
            max_speed: Formats.number(workout.max_speed),
            average_heart_rate: workout.average_heart_rate,
            max_heart_rate: workout.max_heart_rate,
            average_cadence: workout.average_cadence,
            max_cadence: workout.max_cadence,
            average_power: workout.average_power,
            max_power: workout.max_power,
            calories: workout.calories,
            device: workout.source.presence,
            places: Array(workout.places).filter_map { it["name"] if it.is_a?(Hash) },
            equipment_ids: workout.equipments.map(&:to_param),
            import_format: workout.import_format,
            elevation_source: workout.elevation_source,
            contested_metrics: Array(workout.contested_metrics),
            origin: workout.origin,
            # Whether the workout carries a track of its own: false for a
            # positionless recording (which cannot be published yet,
            # docs/dev/NO-GPS.md) and false for a credited workout, whose
            # geometry belongs to its source.
            positioned: workout.positioned?,
            credit: credit_facts,
            created_at: Formats.time(workout.created_at),
            updated_at: Formats.time(workout.updated_at),
            links: links
          }
          return body unless @detail

          body.merge(
            description: workout.description,
            notes: workout.notes,
            analysis_version: workout.analysis_version,
            data_anomalies: anomalies,
            plausible_values: plausible_values,
            import: (import_facts if @workout.recording?),
            publications: publications,
            weather: WeatherSerializer.workout(@workout),
            heart_rate: HeartRateSerializer.workout(@workout)
          )
        end

        private

        # A credit row names who recorded the outing and whether that
        # recording still exists, never the source's identifier
        # (docs/dev/SHARED-ACTIVITIES.md).
        def credit_facts
          return nil unless @workout.credit?

          { recorded_by: SocialSerializers.account(@workout.credited_by), source_deleted: @workout.credit_detached? }
        end

        # A credit row has no track and no original file; a positionless
        # recording has the file but no track.
        def links
          base = Allure::Federation.config.base_url
          path = "/api/rest/v1/workouts/#{@workout.to_param}"
          links = { self: "#{base}#{path}" }
          if @workout.recording?
            links[:original] = "#{base}#{path}/original"
            links[:track] = "#{base}#{path}/track" if @workout.positioned?
          end
          links.merge(web: "#{base}/workouts/#{@workout.to_param}")
        end

        def anomalies
          @workout.anomaly_findings.filter_map do |finding|
            next unless finding.is_a?(Hash)

            {
              kind: finding["kind"],
              tier: finding["tier"] == "major" ? "major" : "minor",
              start_distance: Formats.number(finding["start_distance"]),
              end_distance: Formats.number(finding["end_distance"]),
              start_time: finding["start_time"],
              end_time: finding["end_time"]
            }
          end
        end

        # The value a contested figure would have without the anomaly, as the
        # owner's page shows it under the figure (PLAN_M1.md §8.10).
        def plausible_values
          impact = @workout.data_anomalies.is_a?(Hash) ? @workout.data_anomalies.fetch("impact", {}) : {}
          %w[max_speed distance max_heart_rate].each_with_object({}) do |metric, values|
            plausible = impact.dig(metric, "plausible")
            values[metric] = Formats.number(plausible) unless plausible.nil?
          end
        end

        # Where the workout came from: a file, a Strava archive or a connected
        # service, and how its sport was set (detected from the file, declared
        # by the source, the fallback, or by hand).
        def import_facts
          entry = WorkoutImportEntry.where(workout_id: @workout.id).where.not(status: "duplicate").order(:id).first
          {
            source: @workout.import_connection&.provider || entry&.batch&.source || "file",
            sport_source: entry&.sport_source
          }
        end

        def publications
          (@workout.active_publications.to_a + @workout.scheduled_publications.to_a).map do |publication|
            {
              id: publication.to_param,
              audience: publication.audience,
              status: publication.status,
              published_at: Formats.time(publication.published_at),
              scheduled_for: Formats.time(publication.scheduled_for)
            }
          end
        end
      end
    end
  end
end
