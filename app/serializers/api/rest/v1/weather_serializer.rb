# frozen_string_literal: true

module Api
  module Rest
    module V1
      # Weather in the API (PLAN_WEATHER.md §8): SI units as stored. The owner
      # reads the status, the summary and the hourly series of their workout;
      # a publication carries the summary only, when its profile shared it.
      module WeatherSerializer
        SUMMARY_NUMBERS = %w[
          temperature_min temperature_max temperature_mean apparent_temperature humidity precipitation
          wind_speed wind_gusts wind_direction
        ].freeze
        EXPOSURE_KEYS = %w[head tail cross headwind].freeze

        module_function

        def workout(workout)
          weather = workout.weather
          return nil unless weather

          ready = weather.ready?
          {
            status: weather.status,
            summary: ready ? summary(weather.summary) : nil,
            hours: ready ? weather.series_values.select(&:usable?).map { hour(it) } : []
          }
        end

        def summary(hash)
          return nil unless hash.is_a?(Hash) && hash.present?

          body = { condition: hash["condition"], is_day: hash["is_day"] }
          SUMMARY_NUMBERS.each { |key| body[key.to_sym] = Formats.number(hash[key]) }
          exposure = hash["wind_exposure"]
          body[:wind_exposure] = exposure.is_a?(Hash) ? EXPOSURE_KEYS.to_h { [ it.to_sym, Formats.number(exposure[it]) ] } : nil
          body
        end

        def hour(row)
          {
            time: Formats.time(Time.zone.at(row.time)),
            condition: Allure::Weather::Conditions.token(row.weather_code),
            day: row.day,
            temperature: Formats.number(row.temperature),
            apparent_temperature: Formats.number(row.apparent_temperature),
            humidity: Formats.number(row.humidity),
            precipitation: Formats.number(row.precipitation),
            cloud_cover: Formats.number(row.cloud_cover),
            pressure: Formats.number(row.pressure),
            wind_speed: Formats.number(row.wind_speed),
            wind_direction: Formats.number(row.wind_direction),
            wind_gusts: Formats.number(row.wind_gusts)
          }
        end
      end
    end
  end
end
