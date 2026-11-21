# frozen_string_literal: true

module Allure
  module Insights
    # SI values in the member's units and language (docs/dev/AI.md §3.5). The
    # rules and locale keys are those of WorkoutsHelper and WeatherHelper; the
    # parity spec renders both paths and requires identical strings.
    class Format
      include ActiveSupport::NumberHelper

      def initialize(locale:, unit_system: "metric")
        @locale = locale.to_sym
        @imperial = unit_system.to_s == "imperial"
      end

      attr_reader :locale

      def decimal(value, precision: nil)
        delimiter = t("number.format.delimiter")
        # The number helpers take the decimal separator from the current locale,
        # not from the delimiter: a background job runs in the default one.
        I18n.with_locale(locale) do
          if precision
            number_to_rounded(value, precision:, delimiter:)
          else
            number_to_delimited(value, delimiter:)
          end
        end
      end

      def distance(metres, precision: 2)
        return if metres.nil?

        if imperial?
          miles = Allure::Units.metres_to_miles(metres)
          if miles >= 0.1
            t("units.distance.mi", count: decimal(miles.round(precision), precision:))
          else
            t("units.distance.ft", count: decimal(Allure::Units.metres_to_feet(metres).round))
          end
        else
          km = Allure::Units.metres_to_kilometres(metres)
          if metres >= 1_000
            t("units.distance.km", count: decimal(km.round(precision), precision:))
          else
            t("units.distance.m", count: decimal(metres.round))
          end
        end
      end

      def elevation(metres)
        return if metres.nil?

        if imperial?
          t("units.elevation.ft", count: decimal(Allure::Units.metres_to_feet(metres).round))
        else
          t("units.elevation.m", count: decimal(metres.round))
        end
      end

      def speed(mps, precision: 1)
        return if mps.nil?

        if imperial?
          mph = Allure::Units.metres_per_second_to_miles_per_hour(mps)
          "#{decimal(mph, precision:)} #{t("units.speed.mph")}"
        else
          kmh = Allure::Units.metres_per_second_to_kilometres_per_hour(mps)
          "#{decimal(kmh, precision:)} #{t("units.speed.kmh")}"
        end
      end

      # `seconds_per_basis` is seconds per `basis` metres, the payload's pace.
      def pace(seconds_per_basis, basis: 1_000)
        return if seconds_per_basis.nil?

        if basis.to_i != 1_000
          seconds = seconds_per_basis.to_i
          return format("%d:%02d %s", seconds / 60, seconds % 60, pace_basis_unit(basis))
        end

        seconds = imperial? ? Allure::Units.seconds_per_kilometre_to_seconds_per_mile(seconds_per_basis) : seconds_per_basis
        seconds = seconds.round
        format("%d:%02d %s", seconds / 60, seconds % 60, t(imperial? ? "units.pace.per_mi" : "units.pace.per_km"))
      end

      # An unsigned pace delta in prose (« 12 s /km », « 1 min 36 s /km »), from
      # seconds per `basis` metres; the imperial form converts to the mile.
      def pace_delta(seconds_per_basis, basis: 1_000)
        return if seconds_per_basis.nil?

        seconds = seconds_per_basis.to_i.abs
        seconds = Allure::Units.seconds_per_kilometre_to_seconds_per_mile(seconds) if imperial? && basis.to_i == 1_000
        unit = basis.to_i == 1_000 ? t(imperial? ? "units.pace.per_mi" : "units.pace.per_km") : pace_basis_unit(basis)
        "#{delta_span(seconds)} #{unit}"
      end

      # « 1 min 36 s », « 2 min », « 18 s »: a pace delta reads as a duration,
      # never as a clock time that could be mistaken for the pace itself.
      def delta_span(seconds)
        return t("units.duration.seconds", count: seconds) if seconds < 60

        minutes = seconds / 60
        rest = seconds % 60
        return t("units.duration.minutes", count: minutes) if rest.zero?

        "#{t("units.duration.minutes", count: minutes)} #{t("units.duration.seconds", count: rest)}"
      end

      # An unsigned speed delta, already in the member's units.
      def speed_delta(mps)
        return if mps.nil?

        speed(mps.to_f.abs)
      end

      def duration(seconds)
        return if seconds.nil?

        seconds = seconds.to_i
        hours = seconds / 3_600
        minutes = (seconds % 3_600) / 60
        secs = seconds % 60
        if hours.positive?
          format("%d:%02d:%02d", hours, minutes, secs)
        else
          format("%d:%02d", minutes, secs)
        end
      end

      def duration_human(seconds)
        return if seconds.nil?

        seconds = seconds.to_i
        return t("units.duration.seconds", count: seconds) if seconds < 60

        minutes = seconds / 60
        hours = minutes / 60
        return t("units.duration.hours", count: hours) if (minutes % 60).zero?

        if hours.positive?
          t("units.duration.hours_minutes", hours:, minutes: minutes % 60)
        else
          t("units.duration.minutes", count: minutes)
        end
      end

      # An unsigned span, for prose (« 12 s plus rapide »).
      def duration_span(seconds)
        return if seconds.nil?

        magnitude = seconds.to_i.abs
        magnitude < 60 ? t("units.duration.seconds", count: magnitude) : duration(magnitude)
      end

      # A signed clock delta, as WorkoutsHelper#format_duration_delta renders
      # it; pass a magnitude for the unsigned form.
      def duration_delta(seconds)
        return if seconds.nil?

        seconds = seconds.to_i
        magnitude = seconds.abs
        value = magnitude < 60 ? t("units.duration.seconds", count: magnitude) : duration(magnitude)
        sign = if seconds.positive? then "+" elsif seconds.negative? then "−" else "" end
        "#{sign}#{value}"
      end

      def grade(percent) = t("units.grade.percent", count: decimal(percent, precision: 1))
      def share(fraction) = t("units.grade.percent", count: decimal((fraction.to_f * 100).round))
      def bpm(value) = "#{value} #{t("units.heart_rate.bpm")}"

      def temperature(celsius)
        return if celsius.nil?

        key = imperial? ? "units.temperature.fahrenheit" : "units.temperature.celsius"
        t(key, value: temperature_number(celsius))
      end

      # The weather summary stores precipitation in millimetres (WEATHER.md);
      # WeatherHelper#format_precipitation is the UI's equivalent.
      def precipitation(millimetres)
        return if millimetres.nil?

        if imperial?
          t("units.precipitation.in", value: decimal(Allure::Units.millimetres_to_inches(millimetres), precision: 2))
        else
          t("units.precipitation.mm", value: decimal(millimetres, precision: 1))
        end
      end

      # « 11–16 °C » between two positive values, « −8 à −5 °C » once a bound is
      # negative (WeatherHelper#format_temperature_range).
      def temperature_range(minimum, maximum)
        low = temperature(minimum)
        high = temperature(maximum)
        return low if low == high

        low_value = low.sub(/\s*°[CF]\z/, "")
        key = [ low, high ].any? { it.start_with?("−") } ? "weather.range_signed" : "weather.range"
        t(key, low: low_value, high:)
      end

      def date(time)
        I18n.l(time.to_date, format: :day_month_year, locale:)
      end

      private

      def imperial? = @imperial

      def t(key, **options) = I18n.t(key, locale:, **options)

      def temperature_number(celsius)
        value = imperial? ? Allure::Units.celsius_to_fahrenheit(celsius) : celsius.to_f
        rounded = value.round
        rounded.negative? ? "−#{decimal(rounded.abs)}" : decimal(rounded)
      end

      def pace_basis_unit(basis)
        return t("units.pace.per_500m") if basis.to_i == 500

        "/#{basis} #{t("units.symbols.metre")}"
      end
    end
  end
end
