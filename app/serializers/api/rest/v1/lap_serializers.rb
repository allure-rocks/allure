# frozen_string_literal: true

module Api
  module Rest
    module V1
      # The analysis rows of a workout (PLAN_API.md §6.2, §7.5): laps, splits,
      # best efforts and segment efforts, owner-only, SI units, the columns of
      # the workout page's « Analyse » card.
      module LapSerializers
        module_function

        def recorded(lap)
          {
            source: "recorded",
            number: lap.number,
            name: nil,
            started_at: Formats.time(lap.started_at),
            start_distance: nil,
            end_distance: nil,
            distance: Formats.number(lap.distance),
            elapsed_time: lap.elapsed_time,
            moving_time: lap.moving_time,
            ascent: Formats.number(lap.ascent),
            descent: Formats.number(lap.descent),
            average_speed: Formats.number(lap.average_speed),
            max_speed: Formats.number(lap.max_speed),
            average_heart_rate: lap.average_heart_rate,
            max_heart_rate: lap.max_heart_rate,
            average_cadence: lap.average_cadence,
            average_power: lap.average_power,
            max_power: nil,
            average_grade: nil,
            max_grade: nil,
            trigger: lap.lap_trigger
          }
        end

        def detected(lap)
          {
            source: lap.source,
            number: lap.number,
            name: lap.name,
            started_at: Formats.time(lap.started_at),
            start_distance: Formats.number(lap.start_distance),
            end_distance: Formats.number(lap.end_distance),
            distance: Formats.number(lap.distance),
            elapsed_time: lap.elapsed_time,
            moving_time: lap.moving_time,
            ascent: Formats.number(lap.ascent),
            descent: Formats.number(lap.descent),
            average_speed: Formats.number(lap.average_speed),
            max_speed: Formats.number(lap.max_speed),
            average_heart_rate: lap.average_heart_rate,
            max_heart_rate: lap.max_heart_rate,
            average_cadence: lap.average_cadence,
            average_power: lap.average_power,
            max_power: lap.max_power,
            average_grade: Formats.number(lap.average_grade),
            max_grade: Formats.number(lap.max_grade),
            trigger: nil
          }
        end

        def split(split)
          {
            number: split.number,
            distance: Formats.number(split.distance),
            partial: split.partial,
            started_at: Formats.time(split.start_time),
            elapsed_time: split.elapsed_time.round,
            ascent: Formats.number(split.ascent),
            descent: Formats.number(split.descent),
            average_power: split.average_power,
            grade_adjusted_pace: split.grade_adjusted_pace
          }
        end

        def best_effort(effort, place)
          {
            distance_key: effort.distance_key,
            distance: Formats.number(effort.distance_meters),
            elapsed_time: effort.duration_seconds,
            started_at: Formats.time(effort.started_at),
            start_distance: Formats.number(effort.start_offset_meters),
            end_distance: Formats.number(effort.end_offset_meters),
            sport: effort.sport.slug,
            personal_place: place
          }
        end

        def segment_effort(effort, place, standing)
          segment = effort.segment
          {
            id: effort.to_param,
            segment: { id: segment.to_param, name: segment.name, kind: segment.kind },
            sport: effort.sport.slug,
            occurrence: effort.occurrence_index,
            started_at: Formats.time(effort.started_at),
            start_distance: Formats.number(effort.start_offset_meters),
            distance: Formats.number(effort.distance),
            elapsed_time: effort.elapsed_time,
            moving_time: effort.moving_time,
            ascent: Formats.number(effort.ascent),
            descent: Formats.number(effort.descent),
            average_speed: Formats.number(effort.average_speed),
            average_heart_rate: effort.average_heart_rate,
            max_heart_rate: effort.max_heart_rate,
            average_cadence: effort.average_cadence,
            average_power: effort.average_power,
            max_power: effort.max_power,
            personal_best: effort.personal_best,
            personal_place: place,
            leaderboard: (standing&.ranked ? { rank: standing.rank, participants: standing.participants } : nil)
          }
        end
      end
    end
  end
end
