# frozen_string_literal: true

# Weather presentation (docs/dev/WEATHER.md, DESIGN.md §20.3). Stored values
# are SI; every figure is converted for the viewer's unit system here.
module WeatherHelper
  COMPASS = %w[n ne e se s sw w nw].freeze
  # The vendored Meteocons source, which only the server reads (like the sport
  # icons): the animated set, and its static twin for reduced motion.
  WEATHER_ICON_ROOT = Rails.root.join("app/views/weather/icons")
  WEATHER_ICON_STATIC_ROOT = WEATHER_ICON_ROOT.join("static")
  EXPOSURE_SECTORS = %w[head cross tail].freeze
  # Below this effective component (m/s, ~2 km/h) a split's wind is neither
  # for nor against.
  CALM_HEADWIND = 0.5

  # The owner's card state, or nil when the card stays hidden. Stored weather
  # shows until the owner deletes it, consent withdrawn or not; the pending,
  # failed and missing states only show while the workout may be enriched.
  def workout_weather_state(workout, device_temperature: nil)
    weather = workout.weather
    return :ready if weather&.ready? && weather.summary.present?
    return :device_only if device_temperature && !Workouts::WeatherEligibility.eligible?(workout)
    return nil unless Workouts::WeatherEligibility.eligible?(workout)
    return :missing if weather.nil?

    { "pending" => :pending, "failed" => :failed }[weather.status]
  end

  # The hourly series of the « Météo » analysis tab, owner-only.
  def workout_weather_rows(workout)
    weather = workout.weather
    return [] unless weather&.ready?

    weather.series_values.select(&:usable?)
  end

  # The recorded points the weather analyses read, parsed once per request.
  def workout_weather_points(workout)
    @workout_weather_points ||= {}
    @workout_weather_points[workout.id] ||= Allure::Segments::PointStream.new(
      segments: workout.track_segments, workout_started_at: workout.started_at
    ).call
  end

  # The cumulative distance at each hourly row, for the table's highlight
  # ranges and the markers.
  def workout_weather_row_distances(workout, rows)
    Allure::Weather::Markers.distances(workout_weather_points(workout), rows)
  end

  # The « Météo » tab's markers on the profile and the map
  # (docs/dev/WEATHER.md): owner-only, placed where the weather changes.
  def weather_analysis_markers(workout, rows, distances)
    Allure::Weather::Markers.new(rows:, distances:, total_distance: workout.distance).call.map do |marker|
      row = marker.row
      condition = Allure::Weather::Conditions.token(row.weather_code)
      temperature = format_temperature(row.temperature)
      wind = wind_label(row.wind_speed, row.wind_direction)
      {
        "distance" => marker.distance.round(1),
        "kind" => "weather",
        "svg" => weather_marker_svg(condition, day: row.day != false),
        "name" => [ weather_condition_label(condition), weather_row_time(row.time) ].compact.join(" · "),
        "label" => t("weather.marker.label", temperature:, wind:),
        "temperature" => temperature,
        "wind_direction" => row.wind_direction&.round
      }
    end
  end

  # A marker's icon for the chart and map controllers, which draw it as an
  # image (so its ids need no suffix): both variants, the controller picks
  # one from the reader's motion preference.
  def weather_marker_svg(condition, day:)
    name = Allure::Weather::Icons.name(condition, day:)
    {
      "animated" => Allure::Weather::Icons.markup(name, root: WEATHER_ICON_ROOT),
      "static" => Allure::Weather::Icons.markup(name, root: WEATHER_ICON_STATIC_ROOT)
    }
  end

  # The wind faced on each split (docs/dev/WEATHER.md), from the stored series
  # and the recorded points; empty when the workout has no weather.
  def workout_split_winds(workout, splits)
    rows = workout_weather_rows(workout)
    return [] if rows.empty? || splits.empty?

    points = workout_weather_points(workout)
    ranges = split_ranges(splits).map { |range| [ range[:start], range[:end] ] }
    _total, per_range = Allure::Weather::WindExposure.new(
      points:, rows:, stopped_speed_threshold_mps: workout.sport.stopped_speed_threshold.to_f / 3.6, ranges:
    ).call
    per_range
  end

  # The device's own air-temperature readings (docs/dev/WEATHER.md), derived
  # on read from the stored points: `{ mean:, min:, max: }` or nil.
  def workout_device_temperature(workout)
    return nil unless workout.recording?

    key = Allure::Gpx::PointSerializer::KEY_TEMPERATURE
    values = workout.track_segments.flat_map { |segment| segment.points.filter_map { |point| point[key] } }
    return nil if values.empty?

    { mean: values.sum.to_f / values.length, min: values.min, max: values.max }
  end

  # A below-zero value carries a true minus sign (U+2212), never a hyphen.
  def format_temperature(celsius, unit_system: current_user&.unit_system || "metric")
    return "—" if celsius.nil?

    key = unit_system == "imperial" ? "units.temperature.fahrenheit" : "units.temperature.celsius"
    t(key, value: temperature_number(celsius, unit_system:))
  end

  # « 11–16 °C » between two positive values; « −8 à −5 °C » once a bound is
  # negative, where a dash between two minus signs would not read.
  def format_temperature_range(minimum, maximum, unit_system: current_user&.unit_system || "metric")
    low = format_temperature(minimum, unit_system:)
    high = format_temperature(maximum, unit_system:)
    return low if low == high

    low_value = low.sub(/\s*°[CF]\z/, "")
    key = [ low, high ].any? { it.start_with?("−") } ? "weather.range_signed" : "weather.range"
    t(key, low: low_value, high:)
  end

  def temperature_number(celsius, unit_system:)
    value = unit_system == "imperial" ? Allure::Units.celsius_to_fahrenheit(celsius) : celsius.to_f
    rounded = value.round
    rounded.negative? ? "−#{format_decimal(rounded.abs)}" : format_decimal(rounded)
  end

  def format_wind_speed(mps, unit_system: current_user&.unit_system || "metric")
    format_speed(mps, unit_system:, precision: 0)
  end

  def format_precipitation(millimetres, unit_system: current_user&.unit_system || "metric")
    return "—" if millimetres.nil?

    if unit_system == "imperial"
      t("units.precipitation.in", value: format_decimal(Allure::Units.millimetres_to_inches(millimetres), precision: 2))
    else
      t("units.precipitation.mm", value: format_decimal(millimetres, precision: 1))
    end
  end

  def wind_compass(degrees)
    return nil if degrees.nil?

    t("weather.compass.#{COMPASS[((degrees.to_f % 360) / 45.0).round % 8]}")
  end

  def weather_condition_label(token)
    Allure::Weather::Conditions.valid?(token) ? t("weather.conditions.#{token}") : nil
  end

  # One Meteocons icon, inlined in `currentColor` (docs/dev/WEATHER.md). An
  # animated icon carries its static twin, and CSS shows the one the reader's
  # motion preference allows (DESIGN.md §16); `animated: false` (the hourly
  # table) carries the static one alone. Every id is suffixed so several
  # copies of the same icon on one page never collide, and a class sizes the
  # wrapper at its call site.
  def weather_condition_icon(token, day: nil, animated: true, class_name: nil)
    name = Allure::Weather::Icons.name(token, day: day != false)
    still = weather_icon_svg(name, root: WEATHER_ICON_STATIC_ROOT, class_name: "allure-weather-icon__still")
    motion = weather_icon_svg(name, root: WEATHER_ICON_ROOT, class_name: "allure-weather-icon__motion") if animated
    tag.span(safe_join([ motion, still ].compact),
             class: class_names("allure-weather-icon", { "allure-weather-icon--animated" => animated }, class_name),
             "aria-hidden": "true")
  end

  def weather_icon_svg(name, root:, class_name:)
    markup = Allure::Weather::Icons.markup(name, root:)
    uid = weather_icon_uid
    markup = markup.gsub(/\bid="([^"]+)"/) { "id=\"#{Regexp.last_match(1)}-#{uid}\"" }
    markup = markup.gsub(/url\(#([^)]+)\)/) { "url(##{Regexp.last_match(1)}-#{uid})" }
    markup.sub(/\A<svg /, "<svg class=\"#{class_name}\" focusable=\"false\" ").html_safe
  end

  # A per-request counter keeps each inlined icon's ids unique.
  def weather_icon_uid
    @weather_icon_uid = (@weather_icon_uid || 0) + 1
  end

  # An arrow pointing where the wind blows to (DESIGN.md §20.3), drawn as SVG
  # so its rotation needs no inline style.
  def wind_arrow(from_degrees, size: 16)
    return "".html_safe if from_degrees.nil?

    rotation = (from_degrees.to_f + 180.0) % 360
    tag.svg(width: size, height: size, viewBox: "0 0 24 24", class: "allure-wind-arrow", "aria-hidden": "true",
            focusable: "false") do
      tag.g(transform: "rotate(#{rotation.round} 12 12)") do
        tag.path(d: "M12 3 L12 21 M12 3 L6 9 M12 3 L18 9", fill: "none", stroke: "currentColor", "stroke-width": 2,
                 "stroke-linecap": "round", "stroke-linejoin": "round")
      end
    end
  end

  def wind_label(speed, direction, gusts: nil)
    parts = [ format_wind_speed(speed), wind_compass(direction) ].compact.join(" ")
    gusts.present? ? t("weather.wind_with_gusts", wind: parts, gusts: format_wind_speed(gusts)) : parts
  end

  # The head / cross / tail shares as one bar, drawn as SVG widths (no inline
  # style), with its text equivalent beside it.
  def wind_exposure_bar(exposure)
    shares = EXPOSURE_SECTORS.map { |sector| [ sector, exposure[sector].to_f ] }
    offset = 0.0
    tag.svg(viewBox: "0 0 100 6", preserveAspectRatio: "none", class: "allure-wind-exposure__bar",
            "aria-hidden": "true", focusable: "false") do
      safe_join(shares.filter_map do |sector, share|
        next if share <= 0

        rect = tag.rect(x: offset.round(2), y: 0, width: (share * 100).round(2), height: 6,
                        class: "allure-wind-exposure__#{sector}")
        offset += share * 100
        rect
      end)
    end
  end

  def wind_exposure_shares(exposure)
    EXPOSURE_SECTORS.map do |sector|
      t("weather.exposure.#{sector}", share: number_to_percentage(exposure[sector].to_f * 100, precision: 0))
    end
  end

  def effective_headwind_label(headwind)
    return nil if headwind.nil?

    key = headwind.to_f >= 0 ? "weather.exposure.headwind_against" : "weather.exposure.headwind_behind"
    t(key, speed: format_wind_speed(headwind.to_f.abs))
  end

  # A split's effective wind: « de face 12 km/h » or « de dos 8 km/h ».
  def split_wind_label(result)
    return "—" unless result&.present? && !result.headwind.nil?
    return t("weather.splits.neutral") if result.headwind.abs < CALM_HEADWIND

    key = result.headwind >= 0 ? "weather.splits.head" : "weather.splits.tail"
    t(key, speed: format_wind_speed(result.headwind.abs))
  end

  # A signed wind component for the chart table: positive against.
  def format_signed_wind(mps)
    return "—" if mps.nil?

    sign = mps.to_f.negative? ? "−" : ""
    "#{sign}#{format_wind_speed(mps.to_f.abs)}"
  end

  def weather_row_time(time)
    value = Time.zone.at(time.to_i)
    zone = current_user&.time_zone
    l(zone ? value.in_time_zone(zone) : value, format: :time)
  rescue ArgumentError
    l(Time.zone.at(time.to_i), format: :time)
  end
end
