# frozen_string_literal: true

module WorkoutsHelper
  # Every displayed number goes through the locale (DESIGN.md §3.5): « 4 381 »
  # and « 345,3 » in French, "4,381" and "345.3" in English. Without a
  # precision the value keeps its own digits (a rounded Float stays "10,0");
  # with one, exactly that many decimals are printed.
  def format_decimal(value, precision: nil)
    return "—" if value.nil?

    delimiter = t("number.format.delimiter")
    if precision
      number_with_precision(value, precision:, delimiter:)
    else
      number_with_delimiter(value, delimiter:)
    end
  end

  def format_distance(metres, unit_system: current_user&.unit_system || "metric", precision: 2)
    return "—" if metres.nil?

    if unit_system == "imperial"
      miles = Allure::Units.metres_to_miles(metres)
      if miles >= 0.1
        t("units.distance.mi", count: format_decimal(miles.round(precision)))
      else
        feet = Allure::Units.metres_to_feet(metres)
        t("units.distance.ft", count: format_decimal(feet.round))
      end
    else
      km = Allure::Units.metres_to_kilometres(metres)
      if metres >= 1000
        t("units.distance.km", count: format_decimal(km.round(precision)))
      else
        t("units.distance.m", count: format_decimal(metres.round))
      end
    end
  end

  def format_elevation(metres, unit_system: current_user&.unit_system || "metric")
    return "—" if metres.nil?

    if unit_system == "imperial"
      feet = Allure::Units.metres_to_feet(metres)
      t("units.elevation.ft", count: format_decimal(feet.round))
    else
      t("units.elevation.m", count: format_decimal(metres.round))
    end
  end

  def format_duration(seconds)
    return "—" if seconds.nil?

    seconds = seconds.to_i
    hours = seconds / 3600
    minutes = (seconds % 3600) / 60
    secs = seconds % 60

    if hours.positive?
      format("%d:%02d:%02d", hours, minutes, secs)
    else
      format("%d:%02d", minutes, secs)
    end
  end

  # A signed time difference: "+8 s" under a minute, "−1:12" beyond, with a
  # true minus sign.
  def format_duration_delta(seconds)
    return "—" if seconds.nil?

    seconds = seconds.to_i
    sign = if seconds.positive? then "+" elsif seconds.negative? then "−" else "" end
    magnitude = seconds.abs
    value = magnitude < 60 ? t("units.duration.seconds", count: magnitude) : format_duration(magnitude)
    "#{sign}#{value}"
  end

  def format_speed(mps, unit_system: current_user&.unit_system || "metric", precision: 1)
    return "—" if mps.nil?

    if unit_system == "imperial"
      mph = Allure::Units.metres_per_second_to_miles_per_hour(mps)
      "#{format_decimal(mph, precision:)} #{t('units.speed.mph')}"
    else
      kmh = Allure::Units.metres_per_second_to_kilometres_per_hour(mps)
      "#{format_decimal(kmh, precision:)} #{t('units.speed.kmh')}"
    end
  end

  # Pace renders per kilometre or mile in the viewer's unit system. A sport
  # with a fixed pace basis (rowing's /500 m) always renders over that
  # distance, whatever the unit system, because that is the sport's own
  # convention (DESIGN.md §20.3).
  def format_pace(seconds_per_km, unit_system: current_user&.unit_system || "metric", sport: nil)
    return "—" if seconds_per_km.nil?

    if sport&.pace_basis_metres.present?
      secs = (seconds_per_km.to_f * sport.pace_basis_metres / Allure::Units::METRES_PER_KILOMETRE).round
      return format("%d:%02d %s", secs / 60, secs % 60, pace_basis_unit(sport))
    end

    secs = unit_system == "imperial" ? Allure::Units.seconds_per_kilometre_to_seconds_per_mile(seconds_per_km) : seconds_per_km
    secs = secs.round
    minutes = secs / 60
    remainder = secs % 60
    unit = unit_system == "imperial" ? t("units.pace.per_mi") : t("units.pace.per_km")
    format("%d:%02d %s", minutes, remainder, unit)
  end

  # The unit suffix of a fixed pace basis: the seeded 500 m gets its curated
  # label, any other positive basis falls back to the metre symbol.
  def pace_basis_unit(sport)
    return t("units.pace.per_500m") if sport.pace_basis_metres == 500

    "/#{sport.pace_basis_metres} #{t('units.symbols.metre')}"
  end

  # The persisted geocoded name wins; a route lap falls back to its route name.
  # The generic source-plus-number label is only a last resort for rows without
  # a name column of their own (the mobile cards).
  def detected_lap_name(lap)
    lap.name.presence || (lap.source == "route" && lap.segment_effort&.segment&.name)
  end

  def detected_lap_label(lap)
    detected_lap_name(lap) || "#{t("workouts.show.laps.sources.#{lap.source}")} #{lap.number}"
  end

  def climb_label(climb)
    climb.name.presence || "#{t("workouts.show.laps.sources.climb")} #{climb.number}"
  end

  # Dashed elevation-chart boundaries, in metres along the workout, for the
  # active tab. Each entry is `{ "distance" => Float, "label" => String | nil }`.
  # A distance shared by two laps keeps the labelled boundary.
  def analysis_boundaries(laps)
    boundaries = {}
    laps.each do |lap|
      [ [ lap.start_distance, lap.number.to_s ], [ lap.end_distance, nil ] ].each do |distance, label|
        key = distance.to_f.round
        existing = boundaries[key]
        next if existing && (existing["label"] || label.nil?)

        boundaries[key] = { "distance" => distance.to_f, "label" => label }
      end
    end
    boundaries.values.sort_by { |boundary| boundary["distance"] }
  end

  # Recorded laps have no stored distance window; cumulative lap distances map
  # onto the workout total, scaled when the file's lap total drifts from it.
  def recorded_lap_boundaries(laps, total_distance)
    total = laps.sum { |lap| lap.distance.to_f }
    return [] unless total.positive?

    scale = total_distance.to_f.positive? ? total_distance.to_f / total : 1.0
    running = 0.0
    boundaries = []
    laps.each do |lap|
      running += lap.distance.to_f
      distance = (running * scale).round(1)
      next if distance >= total_distance.to_f - 0.5

      boundaries << { "distance" => distance, "label" => nil }
    end
    boundaries
  end

  def split_boundaries(splits)
    running = 0.0
    splits[0...-1].map do |split|
      running += split.distance.to_f
      { "distance" => running.round(1), "label" => nil }
    end
  end

  def detected_lap_vam(lap)
    return nil if lap.ascent.nil? || lap.elapsed_time.to_i <= 0

    lap.ascent.to_f * 3600 / lap.elapsed_time
  end

  def format_vam(lap)
    vam = detected_lap_vam(lap)
    return "—" if vam.nil?

    "#{format_elevation(vam)}#{t('units.per_hour')}"
  end

  def format_grade(percent)
    return "—" if percent.nil?

    t("units.grade.percent", count: format_decimal(percent, precision: 1))
  end

  def format_descent_rate(lap)
    return "—" if lap.descent.nil? || lap.elapsed_time.to_i <= 0

    rate = lap.descent.to_f * 3600 / lap.elapsed_time
    "#{format_elevation(rate)}#{t('units.per_hour')}"
  end

  def format_power(watts)
    return "—" if watts.nil?

    "#{format_decimal(watts.round)} #{t('units.power.watt')}"
  end

  # The preferred average metric of a sport: pace for pace sports, speed for
  # speed sports, pace with speed as a quiet secondary for pace_and_speed.
  # A sport with a fixed pace basis never falls back to speed.
  def pace_speed_values(average_pace:, average_speed:, sport:)
    if sport.pace_basis_metres.present? && average_pace.nil? && average_speed.to_f.positive?
      average_pace = Allure::Units::METRES_PER_KILOMETRE / average_speed.to_f
    end
    pace = average_pace.nil? ? nil : format_pace(average_pace, sport:)
    speed = average_speed.nil? ? nil : format_speed(average_speed)
    case sport.pace_speed_display
    when "speed" then [ speed || pace, nil ]
    when "pace_and_speed" then [ pace || speed, pace && speed ? speed : nil ]
    else [ pace || speed, nil ]
    end
  end

  def grade_adjusted_pace_metric(workout)
    return "—" unless workout.respond_to?(:grade_adjusted_pace)

    format_pace(workout.grade_adjusted_pace, sport: workout.sport)
  end

  def pace_speed_cell(average_pace:, average_speed:, sport:, grade_adjusted_pace: nil)
    primary, secondary = pace_speed_values(average_pace:, average_speed:, sport:)
    return "—" if primary.nil?

    parts = [ primary ]
    parts << tag.small(secondary, class: "text-secondary fw-normal") if secondary
    if grade_adjusted_pace
      parts << tag.small(
        safe_join([ t("workouts.show.laps.gap"), " ", format_pace(grade_adjusted_pace, sport:) ]),
        class: "text-secondary fw-normal d-block",
        data: tooltip_data(t("workouts.show.metrics.grade_adjusted_pace"))
      )
    end
    safe_join(parts, " ")
  end

  # The effort column of the analysis tables. A power-led virtual ride reads
  # its watts first, with the speed as a quiet second line, exactly like its
  # summary tiles (PLAN_VIRTUAL.md §8); every other sport keeps the pace/speed
  # cell.
  def effort_cell(average_pace:, average_speed:, average_power:, sport:, grade_adjusted_pace: nil)
    unless sport&.power_led? && average_power.present?
      return pace_speed_cell(average_pace:, average_speed:, sport:, grade_adjusted_pace:)
    end

    parts = [ format_power(average_power) ]
    parts << tag.small(format_speed(average_speed), class: "text-secondary fw-normal d-block") if average_speed.present?
    safe_join(parts, " ")
  end

  # The effort column's header follows what its cells print: the pace, the
  # speed, or the watts of a power-led virtual ride.
  def effort_column_label(sport, scope:)
    key = if sport&.power_led?
      "power"
    elsif sport&.pace_speed_display == "speed"
      "speed"
    else
      "pace"
    end
    t("#{scope}.#{key}")
  end

  # A secondary column appears only when at least one row carries the value;
  # a full column of dashes is noise.
  def column_present?(records, attribute)
    records.any? { |record| record.public_send(attribute).present? }
  end

  def split_pace_speed(split)
    distance = split.distance.to_f
    elapsed = split.elapsed_time.to_f
    return [ nil, nil ] unless distance.positive? && elapsed.positive?

    speed = distance / elapsed
    [ (Allure::Units::METRES_PER_KILOMETRE / speed).round, speed ]
  end

  # Global point index -> cumulative distance, matching ChartSeries and
  # PointStream offsets. Built once per workout page; used to place segment
  # efforts on the distance axis for the hover highlight.
  def workout_point_distances(workout)
    @workout_point_distances ||= {}
    @workout_point_distances[workout.id] ||= begin
      distances = []
      offset = 0.0
      workout.track_segments.each do |segment|
        Array(segment.points).each do |point|
          distances << offset + point.fetch(Allure::Gpx::PointSerializer::KEY_DISTANCE, 0).to_f
        end
        offset += segment.distance.to_f
      end
      distances
    end
  end

  def effort_analysis_range(workout, effort)
    distances = workout_point_distances(workout)
    start_distance = distances[effort.start_point_index]
    end_distance = distances[effort.end_point_index]
    return unless start_distance && end_distance && end_distance > start_distance

    [ start_distance, end_distance ]
  end

  # One route-step entry for the chart's timeline: the distance range the step
  # highlights, its display name and detail, the localized source label, and
  # the Tabler icon its timeline dot carries. Climbs and descents both mark the
  # summit, exactly like the chart pictograms. Details are plain text because
  # they travel as JSON.
  def analysis_step(start_distance, end_distance, name:, detail:, source:, icon:)
    {
      "distance" => start_distance.to_f,
      "endDistance" => end_distance.to_f,
      "name" => name,
      "detail" => detail,
      "source" => source,
      "sourceLabel" => t("workouts.show.laps.sources.#{source}"),
      "icon" => icon
    }
  end

  def detected_lap_steps(records)
    records.map do |record|
      analysis_step(record.start_distance, record.end_distance,
                    name: detected_lap_label(record),
                    detail: "#{format_duration(record.elapsed_time)} · #{format_distance(record.distance)}",
                    source: record.source, icon: "repeat")
    end
  end

  def climb_steps(climbs)
    climbs.map do |climb|
      analysis_step(climb.start_distance, climb.end_distance,
                    name: climb_label(climb),
                    detail: "#{format_distance(climb.distance)} · ↑ #{format_elevation(climb.ascent)} · #{format_grade(climb.average_grade)}",
                    source: "climb", icon: "mountain")
    end
  end

  def descent_steps(descents)
    descents.map do |descent|
      analysis_step(descent.start_distance, descent.end_distance,
                    name: detected_lap_label(descent),
                    detail: "#{format_distance(descent.distance)} · ↓ #{format_elevation(descent.descent)}",
                    source: "descent", icon: "mountain")
    end
  end

  def stop_steps(stops)
    stops.map do |stop|
      analysis_step(stop.start_distance, stop.end_distance,
                    name: detected_lap_label(stop),
                    detail: "#{format_duration(stop.elapsed_time)} · #{format_distance(stop.distance)}",
                    source: "stop", icon: "player-pause")
    end
  end

  def segment_effort_steps(workout, efforts)
    efforts.filter_map do |effort|
      range = effort_analysis_range(workout, effort)
      next unless range

      analysis_step(range[0], range[1],
                    name: effort.segment.name,
                    detail: "#{format_duration(effort.elapsed_time)} · #{format_distance(effort.distance)}",
                    source: "segment", icon: "route")
    end
  end

  def recorded_lap_steps(laps, total_distance)
    ranges = recorded_lap_ranges(laps, total_distance)
    laps.each_with_index.map do |lap, index|
      analysis_step(ranges[index][:start], ranges[index][:end],
                    name: "#{t("workouts.show.laps.lap")} #{lap.number}",
                    detail: format_duration(lap.elapsed_time),
                    source: "recorded", icon: "list-numbers")
    end
  end

  # Owner-only tabs for the merged analysis card. Empty sources are absent so
  # the card always opens on the first tab that has data. Elevation tabs carry
  # chart pictogram markers, stops carry stop panels; the older tabs carry
  # dashed boundaries.
  def workout_lap_tabs(workout:, efforts:, recorded:, laps:, climbs:, descents:, stops:, intervals:, splits:, best_efforts: [], best_effort_places: {}, max_climb_lap: nil, segment_ranks: {}, segment_places: {}, segment_gaps: {}, anomalies: [])
    tabs = []
    if efforts.any?
      tabs << lap_tab("segments", "route", "segment_efforts", { efforts:, workout:, segment_ranks:, segment_places:, segment_gaps: },
                      count: efforts.length, steps: segment_effort_steps(workout, efforts))
    end
    if laps.any?
      tabs << lap_tab("detected", "repeat", "detected_laps", { detected_laps: laps, sport: workout.sport },
                      count: laps.length, boundaries: analysis_boundaries(laps), steps: detected_lap_steps(laps))
    end
    if climbs.any?
      tabs << lap_tab("climbs", "mountain", "climbs", { climbs:, sport: workout.sport, max_climb_lap: },
                      count: climbs.length, markers: analysis_markers(climbs, "mountain"), steps: climb_steps(climbs))
    end
    if descents.any?
      tabs << lap_tab("descents", "trending-down", "descents", { descents:, sport: workout.sport },
                      count: descents.length, markers: analysis_markers(descents, "mountain", distance: :start_distance),
                      steps: descent_steps(descents))
    end
    if stops.any?
      tabs << lap_tab("stops", "player-pause", "stops", { stops:, sport: workout.sport },
                      count: stops.length, markers: stop_analysis_markers(stops), steps: stop_steps(stops))
    end
    if intervals.any?
      tabs << lap_tab("intervals", "bolt", "intervals", { intervals:, sport: workout.sport },
                      count: intervals.length, boundaries: analysis_boundaries(intervals))
    end
    if recorded.any?
      tabs << lap_tab("recorded", "list-numbers", "recorded_laps",
                      { laps: recorded, total_distance: workout.distance, sport: workout.sport },
                      count: recorded.length, boundaries: recorded_lap_boundaries(recorded, workout.distance),
                      steps: recorded_lap_steps(recorded, workout.distance))
    end
    if splits.any?
      tabs << lap_tab("splits", "ruler-measure", "splits",
                      { splits:, sport: workout.sport, winds: workout_split_winds(workout, splits) },
                      count: splits.length, boundaries: split_boundaries(splits))
    end
    if (heart_rate = workout_heart_rate_zones(workout))
      tabs << lap_tab("heart_rate", "heart-rate-monitor", "heart_rate_zones", heart_rate,
                      count: heart_rate[:seconds]&.count(&:positive?))
    end
    weather_rows = workout_weather_rows(workout)
    if weather_rows.any?
      distances = workout_weather_row_distances(workout, weather_rows)
      tabs << lap_tab("weather", "temperature-sun", "weather_hours", { rows: weather_rows, distances: },
                      count: weather_rows.length, markers: weather_analysis_markers(workout, weather_rows, distances))
    end
    if best_efforts.any?
      tabs << lap_tab("best_efforts", "stopwatch", "best_efforts",
                      { best_efforts: ordered_best_efforts(workout, best_efforts), sport: workout.sport,
                        places: best_effort_places },
                      count: best_efforts.length)
    end
    if anomalies.any?
      tabs << lap_tab("anomalies", "alert-triangle", "anomalies", { workout:, anomalies: },
                      count: anomaly_flagged_count(workout, anomalies))
    end
    tabs
  end

  # The tab lists standard distances in their course order, not by duration.
  def ordered_best_efforts(workout, best_efforts)
    profile = Allure::Gpx::BestEfforts.profile_for(workout.sport.slug)
    return best_efforts unless profile

    order = Allure::Gpx::BestEfforts::PROFILES.fetch(profile)
    best_efforts.sort_by { |effort| order.index(effort.distance_key) || order.length }
  end

  def best_effort_pace(effort)
    return nil unless effort.distance_meters.to_f.positive?

    (effort.duration_seconds * 1_000.0 / effort.distance_meters.to_f).round
  end

  # Every visible record the workout currently holds, in badge order: the
  # classic types first, then the best-effort distances.
  def held_record_labels(records, effort_records, sport:)
    labels = records.select { |record| Record.visible_type?(record.record_type, sport) }
      .map { |record| t("records.types.#{record.record_type.downcase}") }
    labels + effort_records.map { |record| t("records.distances.#{record.distance_key}") }
  end

  # Labels for a published snapshot payload. The publisher already filtered the
  # tokens by the sport's readable types and the enabled metrics, so they render
  # as-is.
  def snapshot_record_labels(record_types, record_distances)
    Array(record_types).map { |type| t("records.types.#{type.downcase}") } +
      Array(record_distances).map { |key| t("records.distances.#{key}") }
  end

  # Metric key => trophy label for the summary tiles whose value is a record.
  def record_labels_by_metric_key(records, sport:)
    visible = records.select { |record| Record.visible_type?(record.record_type, sport) }
    record_labels_from_types(visible.map(&:record_type))
  end

  # Same mapping for a snapshot token list or a bare type list.
  def record_labels_from_types(record_types)
    Array(record_types).each_with_object({}) do |type, labels|
      metric = Record::TILE_METRIC_KEYS[type]
      labels[metric.to_sym] = t("records.types.#{type.downcase}") if metric
    end
  end

  # Chart pictogram markers. Climbs anchor on their end distance (the summit)
  # and descents on their start distance (their summit too): both mark summits
  # with the same glyph, since a segment itself is a range, not a point.
  def analysis_markers(laps, glyph, distance: :end_distance)
    laps.map do |lap|
      {
        "distance" => lap.public_send(distance).to_f,
        "glyph" => glyph,
        "label" => lap.name.presence
      }
    end
  end

  def stop_analysis_markers(stops)
    stops.map do |stop|
      {
        "distance" => stop.start_distance.to_f,
        "glyph" => "stop",
        "label" => format_duration(stop.elapsed_time),
        "name" => stop.name.presence
      }
    end
  end

  # Row attributes consumed by workout_tabs_controller to highlight the matching
  # range on the elevation chart and the map while the row is hovered, focused,
  # or pinned. `source` and `label` drive the stop panels. Applied to both the
  # desktop table row and its mobile card list item.
  def analysis_row_attributes(start_distance, end_distance, source: nil, label: nil)
    {
      tabindex: 0,
      data: {
        analysis_range: "",
        start_distance: start_distance.to_f,
        end_distance: end_distance.to_f,
        analysis_source: source,
        analysis_label: label
      }
    }
  end

  # Aligned with `laps`; cumulative lap distances map onto the workout total
  # exactly like `recorded_lap_boundaries`, so the hover band and the dashed
  # boundary lines cannot drift apart.
  def recorded_lap_ranges(laps, total_distance)
    total = laps.sum { |lap| lap.distance.to_f }
    scale = total.positive? && total_distance.to_f.positive? ? total_distance.to_f / total : 1.0
    running = 0.0
    laps.map do |lap|
      start_distance = (running * scale).round(1)
      running += lap.distance.to_f
      { start: start_distance, end: (running * scale).round(1) }
    end
  end

  def split_ranges(splits)
    running = 0.0
    splits.map do |split|
      start_distance = running
      running += split.distance.to_f
      { start: start_distance.round(1), end: running.round(1) }
    end
  end

  def lap_tab(key, icon, partial, locals, count:, boundaries: nil, markers: nil, steps: nil)
    {
      key:,
      icon:,
      pane: "workout-laps-#{key}",
      partial:,
      locals:,
      count:,
      boundaries:,
      markers:,
      steps:
    }
  end

  def format_started_at(time)
    return "—" if time.nil?

    zone = current_user&.time_zone || Time.zone
    l(time.in_time_zone(zone), format: :long)
  rescue StandardError
    l(time, format: :long)
  end

  # Relative day with the clock time, for surfaces that read as a stream
  # ("Aujourd'hui 14:30", "Hier 07:30", "Avant-hier 08:02", otherwise
  # "12 sept. 08:02"). Anchored on the viewer's calendar day.
  def smart_started_at(time)
    return "—" if time.nil?

    zone = current_user&.time_zone || Time.zone
    local = time.in_time_zone(zone)
    day = local.to_date
    today = Time.find_zone(zone)&.today || Date.current
    label = case day
    when today then t("workouts.dates.today")
    when today - 1 then t("workouts.dates.yesterday")
    when today - 2 then t("workouts.dates.day_before_yesterday")
    end
    clock = l(local, format: :time)
    label ? "#{label} #{clock}" : l(local, format: :short_datetime)
  rescue StandardError
    l(time, format: :short_datetime)
  end

  # Human-scale duration for compact surfaces: "45 s", "48 min", "2 h",
  # "1 h 25 min". Seconds only appear under a minute; minutes are rounded
  # once past the hour.
  def format_duration_human(seconds)
    return "—" if seconds.nil?

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

  def sport_display_name(sport)
    sport.translated_name
  rescue I18n::MissingTranslationData
    sport.label
  end

  def sport_options_for_select
    Sport.alphabetical.map { |sport| [ sport_display_name(sport), sport.id ] }
  end

  # A manual entry field's own refusals, under the field (PLAN_MANUAL_ENTRY.md §5).
  def manual_entry_error(form, field)
    messages = form.errors.full_messages_for(field)
    return if messages.empty?

    tag.div(messages.uniq.join(" "), class: "invalid-feedback d-block")
  end

  # Targets for a generic-sport default: the curated variant list for that
  # generic (PLAN_M1.md §3.4.2), in alphabetical order.
  def sport_default_options_for(generic_slug)
    slugs = Sport::DEFAULT_TARGET_SLUGS.fetch(generic_slug.to_s, [])
    Sport.alphabetical(Sport.where(slug: slugs)).map { |sport| [ sport_display_name(sport), sport.id ] }
  end

  def workout_display_title(workout)
    workout.title.presence || t(
      "workouts.defaults.title",
      sport: sport_display_name(workout.sport),
      date: l(workout.started_at.in_time_zone(current_user&.time_zone || Time.zone).to_date)
    )
  end

  # The owner's publication badges (DESIGN.md §10.4): one per active
  # publication's audience, narrowest first (docs/dev/PUBLISHING.md), else one
  # per scheduled publication in the tint of the audience it will reach, else
  # « not published » — left out where `unpublished: false` (cards and phone
  # rows mark only a shared or scheduled workout). Reads the two preloaded
  # associations, so a list never queries per card.
  def workout_publication_badges(workout, fit: :auto, unpublished: true)
    rank = ->(audience) { WorkoutPublication.audience_rank(audience) }
    active = workout.active_publications.map(&:audience).uniq.sort_by(&rank)
    scheduled = workout.scheduled_publications.map(&:audience).uniq.sort_by(&rank)
    badges = if active.any?
      active.map { |audience| publication_badge(audience, fit:) }
    elsif scheduled.any?
      scheduled.map { |audience| publication_badge("scheduled", audience:, fit:) }
    elsif unpublished
      [ publication_badge("unpublished", fit:) ]
    else
      []
    end
    safe_join(badges)
  end

  # The profiles a publish form offers (docs/dev/PUBLISHING.md): those whose
  # audience no live publication holds yet, plus — when replacing — the
  # replaced publication's own audience.
  def publish_form_profiles(workout, profiles, replaced: nil)
    taken = workout.live_audiences - [ replaced&.audience ]
    profiles.reject { |profile| taken.include?(profile.audience) }
  end

  # The card view's month sections (DESIGN.md §20.4): adjacent cards sharing
  # the activity's calendar month in the viewer's zone, in list order.
  # `chunk_while` never reorders — only a date-sorted list may be sectioned.
  def workout_months(workouts)
    workouts.chunk_while { |a, b| workout_month_for(a) == workout_month_for(b) }
            .map { |group| [ workout_month_for(group.first), group ] }
  end

  def workout_month_for(workout)
    workout.started_at.in_time_zone(current_user&.time_zone.presence || Time.zone).to_date.beginning_of_month
  end

  # The workout's places in route order, owner-only: "Valmorin · Cimefroide · Rochelune".
  # Names only — never a kind, a role, or a coordinate.
  def workout_place_label(workout)
    names = Array(workout.places).filter_map do |entry|
      place = entry.respond_to?(:to_h) ? entry.to_h : {}
      name = (place["name"] || place[:name]).to_s.strip
      name.presence&.truncate(120)
    end
    return if names.empty?

    names.join(" · ")
  end

  # A recording imported without a GPS position (PLAN_NO_GPS.md §9) carries no
  # elevation at all, and one whose file recorded no distance either is a
  # duration-only session: both would render zeros the device never measured.
  # A publication view is always a positioned snapshot.
  def workout_positionless?(workout) = workout.is_a?(Workout) && workout.positionless?

  def workout_distance_recorded?(workout)
    workout.is_a?(Workout) ? workout.distance_recorded? : workout.distance.to_f.positive?
  end

  # A positionless recording with no distance plots elapsed time: there is no
  # kilometre to place a point at (PLAN_NO_GPS.md §9).
  def workout_time_axis?(workout) = workout_positionless?(workout) && !workout_distance_recorded?(workout)

  # The list row's distance and ascent cells: a figure the file did not
  # record reads as a dash, exactly like an unrecorded channel on the summary.
  def workout_table_distance(workout)
    workout_time_axis?(workout) || workout_manual_hidden?(workout, :distance) ? "—" : format_distance(workout.distance)
  end

  def workout_table_ascent(workout)
    workout_positionless?(workout) || workout_manual_hidden?(workout, :ascent) ? "—" : format_elevation(workout.ascent)
  end

  # A manual entry's figure left empty reads as a dash (PLAN_MANUAL_ENTRY.md §7).
  def workout_manual_hidden?(workout, key) = workout.is_a?(Workout) && workout.manual? && !workout.metric_visible?(key)

  def workout_metric_items(workout)
    sport = workout.sport
    items = workout_metric_definitions(workout).filter_map do |key, (value, has_unit)|
      next unless workout.metric_visible?(key)
      next if sport.pace_basis_metres.present? && %i[average_speed max_speed].include?(key)

      { key:, label: t("workouts.show.metrics.#{key}"), value:, has_unit: }
    end

    primary_keys = workout_primary_metric_keys(workout)
    items.map { |item| item.merge(primary: primary_keys.include?(item[:key]), priority: primary_keys.index(item[:key])) }
  end

  def workout_metric_definitions(workout)
    sport = workout.sport
    {
      distance: [ format_distance(workout.distance), true ],
      duration: [ format_duration(workout.duration), false ],
      moving_time: [ format_duration(workout.moving_time), false ],
      pause_time: [ format_duration(workout.pause_time), false ],
      ascent: [ format_elevation(workout.ascent), true ],
      descent: [ format_elevation(workout.descent), true ],
      min_elevation: [ format_elevation(workout.min_elevation), true ],
      max_elevation: [ format_elevation(workout.max_elevation), true ],
      average_speed: [ format_speed(workout.average_speed), true ],
      max_speed: [ format_speed(workout.max_speed), true ],
      average_pace: [ format_pace(workout.average_pace, sport:), true ],
      best_pace: [ format_pace(workout.best_pace, sport:), true ],
      grade_adjusted_pace: [ grade_adjusted_pace_metric(workout), true ],
      average_heart_rate: [ metric_with_unit(workout.average_heart_rate, t("units.heart_rate.bpm")), true ],
      max_heart_rate: [ metric_with_unit(workout.max_heart_rate, t("units.heart_rate.bpm")), true ],
      average_cadence: [ metric_with_unit(workout.average_cadence, sport.cadence_unit), true ],
      max_cadence: [ metric_with_unit(workout.max_cadence, sport.cadence_unit), true ],
      average_power: [ metric_with_unit(workout.average_power, t("units.power.watt")), true ],
      max_power: [ metric_with_unit(workout.max_power, t("units.power.watt")), true ],
      calories: [ metric_with_unit(workout.calories, t("units.energy.kilocalorie")), true ],
      points_count: [ workout.points_count || "—", false ]
    }
  end

  # The primary tile keys, in reading order. A fixed-basis sport (rowing)
  # prefers average power as its fourth tile when the file recorded it and
  # falls back to ascent otherwise; its speed tiles are dropped entirely, as
  # km/h is not a rowing metric. A power-led virtual sport (cycling virtual,
  # PLAN_VIRTUAL.md §8) leads with average power in place of its speed when
  # the recording carries it: the platform's speed is a game output, the watts
  # are the athlete's effort. A positionless recording promotes the channels it
  # did record — power, heart rate, calories — because its elevation tiles
  # never exist and a duration-only session has no distance.
  #
  # `available:` names the keys the caller may show. The credited metric set
  # carries no power, so a participant falls back to the speed rather than
  # losing a tile.
  def workout_primary_metric_keys(workout, available: nil)
    sport = workout.sport
    preferred_average = if power_led_primary?(workout, available)
      :average_power
    elsif sport.pace_speed_display == "speed"
      :average_speed
    else
      :average_pace
    end
    # A manual entry leads with what its owner typed in (PLAN_MANUAL_ENTRY.md §7).
    if workout.is_a?(Workout) && workout.manual?
      base = workout.distance_recorded? ? [ :distance, :moving_time, preferred_average ] : [ :moving_time ]
      extras = %i[ascent average_power average_heart_rate calories]
        .select { |key| workout.metric_visible?(key) }
        .excluding(preferred_average)
      return (base + extras).first(4)
    end
    unless workout_positionless?(workout)
      fourth_key = sport.pace_basis_metres.present? && workout.average_power.present? ? :average_power : :ascent
      return [ :distance, :moving_time, preferred_average, fourth_key ]
    end

    unless workout_distance_recorded?(workout)
      return [ :moving_time, *%i[average_power average_heart_rate calories].select { |key| workout.public_send(key).present? } ]
    end

    fourth_key = %i[average_power average_heart_rate calories].excluding(preferred_average)
      .find { |key| workout.public_send(key).present? }
    [ :distance, :moving_time, preferred_average, fourth_key ].compact
  end

  # Whether the workout leads with its watts: a power-led virtual sport whose
  # recording carries average power the caller may show. A publication whose
  # profile withholds power, and the credited metric set, fall back to speed.
  def power_led_primary?(workout, available)
    return false unless workout.sport&.power_led?
    return false if available && !available.include?(:average_power)

    workout.average_power.present?
  end

  # The credited metric set (PLAN_TOGETHER.md §4.1): the only metrics a
  # participant ever reads from a source workout. Physiological channels,
  # calories, the device, the description, and the places never appear.
  PARTICIPANT_METRIC_KEYS = %i[
    distance moving_time duration ascent descent
    average_speed max_speed average_pace best_pace
  ].freeze

  def participant_metric_items(workout)
    items = workout_metric_items(workout).select { |item| PARTICIPANT_METRIC_KEYS.include?(item[:key]) }
    # The credited set has no power, so a power-led source falls back to the
    # speed here instead of losing its third tile.
    primary_keys = workout_primary_metric_keys(workout, available: PARTICIPANT_METRIC_KEYS)
    items.map { |item| item.merge(primary: primary_keys.include?(item[:key]), priority: primary_keys.index(item[:key])) }
  end

  # A metric the file did not record renders as a dash; the summary hides
  # those and names them once instead.
  def workout_metric_recorded?(item) = item.fetch(:value).to_s != "—"

  # The channels a set of unrecorded metrics belongs to, deduplicated in
  # display order: the average and the maximum heart rate are one "heart rate".
  METRIC_FAMILIES = {
    average_heart_rate: :heart_rate, max_heart_rate: :heart_rate,
    average_cadence: :cadence, max_cadence: :cadence,
    average_power: :power, max_power: :power,
    min_elevation: :elevation, max_elevation: :elevation, descent: :elevation, ascent: :elevation
  }.freeze

  def workout_missing_metric_labels(items)
    items.reject { |item| workout_metric_recorded?(item) }.filter_map do |item|
      family = METRIC_FAMILIES[item.fetch(:key)]
      next t("workouts.show.metrics.families.#{family}") if family

      label = item.fetch(:label)
      label.sub(/\A\p{Lu}(?=\p{Ll})/) { |letter| letter.downcase }
    end.uniq
  end

  def workout_metric_value(item)
    value = item.fetch(:value).to_s
    return tag.span("—", aria: { label: t("workouts.show.metrics.not_recorded") }) if value == "—"
    return value unless item.fetch(:has_unit)

    number, separator, unit = value.rpartition(" ")
    return value if separator.empty?

    safe_join([ number, " ", tag.small(unit, class: "text-secondary fw-normal") ])
  end

  def workout_map_summary(workout, segment_count:)
    facts = []
    facts << t("workouts.show.map.summary_distance", value: format_distance(workout.distance)) if workout.metric_visible?(:distance)
    facts << t("workouts.show.map.summary_ascent", value: format_elevation(workout.ascent)) if workout.metric_visible?(:ascent)
    facts << t("workouts.show.map.summary_segments", count: segment_count) if segment_count.positive?
    facts.join(" · ")
  end

  # The series the chart draws and lists in its data table, in reading order.
  # A power-led virtual ride opens on its watts — the effort it measures — and
  # the selector keeps the speed (PLAN_VIRTUAL.md §8).
  def workout_chart_display_series(workout, available_series)
    available = available_series.map(&:to_sym)
    display = []
    display << :elevation if available.include?(:elevation)
    display << :power if available.include?(:power) && workout.sport&.power_led?
    if available.include?(:speed)
      display << :pace if %w[pace pace_and_speed].include?(workout.sport.pace_speed_display)
      display << :speed if %w[speed pace_and_speed].include?(workout.sport.pace_speed_display)
    end
    display.concat(%i[heart_rate cadence power temperature device_temperature headwind].select { |key| available.include?(key) })
    display.uniq
  end

  def workout_chart_secondary_options(workout, available_series)
    workout_chart_display_series(workout, available_series)
      .excluding(:elevation)
      .map { |key| [ t("workouts.show.chart.series.#{key}"), key ] }
  end

  def format_workout_chart_value(key, value, sport:)
    return "—" if value.nil?

    case key.to_sym
    when :elevation then format_elevation(value)
    when :speed then format_speed(value)
    when :pace then value.to_f.positive? ? format_pace(1000.0 / value.to_f, sport:) : "—"
    when :heart_rate then metric_with_unit(value, t("units.heart_rate.bpm"))
    when :cadence then metric_with_unit(value, sport.cadence_unit)
    when :power then metric_with_unit(value, t("units.power.watt"))
    when :temperature, :device_temperature then format_temperature(value)
    when :headwind then format_signed_wind(value)
    else "—"
    end
  end

  # The profile page renders the published representation even for the owner
  # (`snapshot_only`), so the owner never reads complete source values from the
  # public URL (docs/dev/PUBLISHING.md).
  #
  # The publication shown is the narrowest serving the viewer
  # (docs/dev/PUBLISHING.md) unless the caller already chose it.
  def workout_display(workout, snapshot_only: false, sport_catalog: nil, publication: nil)
    return workout if !snapshot_only && workout.user == current_user

    publication ||= Workouts::PublicationResolver.new(workout:, user: current_user).call
    principal = Workouts::PublicationPrincipal.browser(current_user)
    policy = Workouts::PublicationPolicy.new(publication:, principal:)
    return Workouts::PublicationView.new(publication, principal:, sport_catalog:) if policy.allowed?

    raise ActiveRecord::RecordNotFound
  end

  def pagy_bootstrap_nav(pagy)
    return "" if pagy.nil? || pagy.last <= 1

    html = +""
    html << %(<nav aria-label="#{t('pagy.label')}"><ul class="pagination mb-0">)

    # previous
    if pagy.page > 1
      html << %(<li class="page-item"><a class="page-link" href="#{pagy_url_for(pagy, pagy.page - 1)}" aria-label="#{t('pagy.previous')}">&#8249;</a></li>)
    else
      html << %(<li class="page-item disabled"><span class="page-link">&#8249;</span></li>)
    end

    series = begin
      pagy.send(:series)
    rescue StandardError
      (1..pagy.last).to_a
    end
    series.each do |item|
      case item
      when Integer
        html << %(<li class="page-item"><a class="page-link" href="#{pagy_url_for(pagy, item)}">#{item}</a></li>)
      when String
        html << %(<li class="page-item active"><span class="page-link">#{item}</span></li>)
      when :gap
        html << %(<li class="page-item disabled"><span class="page-link">&hellip;</span></li>)
      end
    end

    if pagy.page < pagy.last
      html << %(<li class="page-item"><a class="page-link" href="#{pagy_url_for(pagy, pagy.page + 1)}" aria-label="#{t('pagy.next')}">&#8250;</a></li>)
    else
      html << %(<li class="page-item disabled"><span class="page-link">&#8250;</span></li>)
    end

    html << "</ul></nav>"
    html.html_safe
  end

  # Compact top pagination: previous / position / next only. The bottom nav
  # carries the full page series.
  def pagy_bootstrap_compact_nav(pagy)
    return "" if pagy.nil? || pagy.last <= 1

    html = +""
    html << %(<nav aria-label="#{t('pagy.label')}"><ul class="pagination pagination-sm mb-0">)
    if pagy.page > 1
      html << %(<li class="page-item"><a class="page-link" href="#{pagy_url_for(pagy, pagy.page - 1)}" aria-label="#{t('pagy.previous')}">&#8249;</a></li>)
    else
      html << %(<li class="page-item disabled"><span class="page-link">&#8249;</span></li>)
    end
    html << %(<li class="page-item disabled"><span class="page-link">#{t('pagy.position', page: pagy.page, last: pagy.last)}</span></li>)
    if pagy.page < pagy.last
      html << %(<li class="page-item"><a class="page-link" href="#{pagy_url_for(pagy, pagy.page + 1)}" aria-label="#{t('pagy.next')}">&#8250;</a></li>)
    else
      html << %(<li class="page-item disabled"><span class="page-link">&#8250;</span></li>)
    end
    html << "</ul></nav>"
    html.html_safe
  end

  # Filter-bar state (§13). Only allowlisted URL params round-trip; anything
  # else never lands in a chip link or a form field. The display mode is the
  # rendered state's, not a re-read param, so every generated link carries it
  # (§13.1) — an explicit `view:` override still wins, and `view: nil` drops it.
  def workout_filter_params(overrides = {})
    permitted = params.permit(:period, :from, :to, :publication, :commute, :q, :place, :sort, :direction,
                              sports: [])
    merged = permitted.to_h.merge(overrides.stringify_keys)
    merged["view"] = workout_view_param unless overrides.key?(:view) || overrides.key?("view")
    merged.delete("page") unless overrides.key?(:page) || overrides.key?("page")
    merged.reject { |_, value| value.blank? }
  end

  def workout_active_sport_ids
    Array(params[:sports]).map(&:to_s).select { |id| id.match?(/\A\d+\z/) }.uniq
  end

  # The display mode as a URL parameter (§13.1): card is the default and
  # contributes nothing, table is explicit. Every action that keeps the
  # visitor on the list — filtering, sorting, clearing, paginating — must carry
  # it, so only the view switch itself changes it.
  def workout_view_param = @view == "table" ? "table" : nil

  # The filter form's hidden field: what the pills, the selects, the sort and
  # the search submit, so a form submission never silently resets the mode.
  def workout_view_field
    return if workout_view_param.nil?

    hidden_field_tag :view, "table"
  end

  # Clearing the filters drops the filter params only: the page resets, the
  # sort and the display mode stay (§13.3).
  def workout_clear_filters_path
    workouts_path(view: workout_view_param)
  end

  # One sortable table header (§10.5): the label links to the same page sorted
  # by this column, first ascending then toggling; the cell carries `aria-sort`
  # and the active column shows its direction. Every active filter round-trips.
  def workout_sort_header(label, field, align: nil)
    current = filter_sort == field ? filter_direction : nil
    next_direction = current == "asc" ? "desc" : "asc"
    state = { "asc" => "ascending", "desc" => "descending" }.fetch(current, "none")
    icon = { "asc" => "ti-sort-ascending", "desc" => "ti-sort-descending" }.fetch(current, "ti-arrows-sort")

    tag.th(scope: "col", "aria-sort": state, class: class_names("allure-sort-cell", "text-end" => align == :end)) do
      link_to workouts_path(workout_filter_params(sort: "#{field}_#{next_direction}")),
            class: class_names("allure-sort-link", "allure-sort-link--active" => current.present?),
            aria: { label: t("workouts.index.table.sort_by", column: label) } do
        safe_join([ label, tag.i("", class: class_names("ti", icon, "ms-1"), aria: { hidden: true }) ], " ")
      end
    end
  end

  # The filters the drawer itself owns: the custom range's dates, the
  # non-default publication and commute presets, the place and the search. The
  # sport selection and a preset period live in the always-visible toolbar, so
  # they never land in its badge nor in a chip (§10.6). Sort, direction, page
  # and view are not filters.
  def workout_panel_filter_count
    count = 0
    count += 1 if params[:period] == "custom"
    count += 1 if WorkoutsController::FILTER_PUBLICATIONS.include?(params[:publication]) && params[:publication] != "all"
    count += 1 if WorkoutsController::FILTER_COMMUTES.include?(params[:commute]) && params[:commute] != "all"
    count += 1 if params[:place].present?
    count += 1 if params[:q].present?
    count
  end

  def workout_panel_filters_active?
    workout_panel_filter_count.positive?
  end

  def workout_period_active?
    WorkoutsController::FILTER_PERIODS.include?(params[:period]) && params[:period] != "all"
  end

  # Any active filter at all, including the sport selection and the period:
  # the clear-all action, the filtered count and the filtered empty state.
  def workout_filters_active?
    workout_panel_filters_active? || workout_period_active? || workout_active_sport_ids.any?
  end

  # The drawer's active filters as removable chips; the sports and a preset
  # period already show in their own toolbar controls, and only a custom
  # range earns a chip, because its dates live in the drawer. Each remove link
  # names the filter it removes; changing filters resets the page.
  def workout_filter_chips
    chips = []
    if params[:period] == "custom"
      chips << {
        label: workout_period_label,
        url: workouts_path(workout_filter_params(period: nil, from: nil, to: nil))
      }
    end
    if WorkoutsController::FILTER_PUBLICATIONS.include?(params[:publication]) && params[:publication] != "all"
      chips << {
        label: t("workouts.index.filters.publications.#{params[:publication]}"),
        url: workouts_path(workout_filter_params(publication: nil))
      }
    end
    if WorkoutsController::FILTER_COMMUTES.include?(params[:commute]) && params[:commute] != "all"
      chips << {
        label: t("workouts.index.filters.commutes.#{params[:commute]}"),
        url: workouts_path(workout_filter_params(commute: nil))
      }
    end
    if params[:place].present?
      chips << { label: params[:place].to_s.strip, url: workouts_path(workout_filter_params(place: nil)) }
    end
    if params[:q].present?
      chips << { label: params[:q].to_s.strip, url: workouts_path(workout_filter_params(q: nil)) }
    end
    chips
  end

  def workout_period_label
    key = WorkoutsController::FILTER_PERIODS.include?(params[:period]) ? params[:period] : "all"
    label = t("workouts.index.filters.periods.#{key}")
    return label unless key == "custom"

    dates = [ params[:from], params[:to] ].map(&:presence).compact
    dates.any? ? "#{label} (#{dates.join(" – ")})" : label
  end

  # Live publication preview (§19.1): exactly what the selected profile
  # would share, followed by what is never shared.
  def publication_preview_fields(profile)
    settings = profile.settings
    fields = []
    fields << t("publishing_profiles.settings.title") if settings["title"]
    fields << t("publishing_profiles.settings.description") if settings["description"]
    metrics = Array(settings["metrics"])
    fields << t("workouts.publish.preview.metrics", count: metrics.size) if metrics.any?
    fields << t("publishing_profiles.settings.route") if settings["route"]
    fields << t("publishing_profiles.settings.gpx") if settings["gpx"]
    fields << t("publishing_profiles.settings.records") if settings["records"]
    fields << t("publishing_profiles.settings.route_image") if settings["route_image"]
    fields << t("publishing_profiles.settings.device") if settings["device"]
    fields << t("publishing_profiles.settings.commute") if settings["commute"]
    fields << t("publishing_profiles.settings.weather") if settings["weather"]
    if settings["photos"]
      fields << t("publishing_profiles.settings.photos")
      fields << t("publishing_profiles.settings.photo_captions") if settings["photo_captions"]
      fields << t("publishing_profiles.settings.photo_positions") if settings["photo_positions"]
    end
    fields
  end

  # The optional fields the selected profile leaves out, for the "not shared"
  # list beside the §19.1 shared list. A partial metric selection is not a
  # withheld field: the shared list already counts the included metrics.
  PUBLICATION_OPTIONAL_FIELDS = %w[title description metrics route gpx records route_image device commute weather photos].freeze

  def publication_withheld_fields(profile)
    settings = profile.settings
    PUBLICATION_OPTIONAL_FIELDS.filter_map do |key|
      if key == "metrics"
        t("publishing_profiles.settings.metrics_title") if Array(settings["metrics"]).empty?
      elsif !settings[key]
        t("publishing_profiles.settings.#{key}")
      end
    end
  end

  def publication_preview_text(profile)
    fields = publication_preview_fields(profile)
    shared = fields.any? ? t("workouts.publish.preview.shared", fields: fields.join(", ")) : nil
    [ shared, t("workouts.publish.preview.never") ].compact.join(" ")
  end

  # The owner can switch between the recorded and the terrain profile only when
  # the instance configured a provider, the account opted in, and there is a
  # recorded profile to fall back to (PLAN_ELEVATION.md §6).
  def elevation_source_control?(workout)
    return false unless current_user && current_user == workout.user
    return false unless Allure::Elevation::Config.configured?
    return false unless current_user.elevation_enrichment_enabled?

    workout.sport.records_elevation? && workout.recorded_elevation?
  end

  def workout_elevation_absent?(workout)
    workout.min_elevation.nil? && workout.max_elevation.nil?
  end

  # Why an elevation-less owner workout shows no altitude, and the one action
  # that fixes it where one exists (PLAN_ELEVATION.md §6). Nil means the
  # summary needs no notice.
  def workout_elevation_notice(workout)
    return nil unless current_user && current_user == workout.user
    return nil unless workout_elevation_absent?(workout)
    return :sport_without_elevation unless workout.sport.records_elevation?
    return :pending if workout.elevation_source_requested.present?
    return :failed if workout.elevation&.failed?
    return :unavailable if workout.elevation&.unavailable?
    return :provider_missing unless Allure::Elevation::Config.configured?
    return :opt_out unless current_user.elevation_enrichment_enabled?
    return :idle if workout.elevation.nil?
    return :idle if workout.elevation.status.in?(Workouts::ElevationEnricher::USABLE_STATUSES) && workout.elevation_source != "dem"

    nil
  end

  private

  def metric_with_unit(value, unit)
    return "—" if value.nil?
    formatted = value.is_a?(Numeric) ? format_decimal(value) : value.to_s
    return formatted if unit.blank?

    "#{formatted} #{unit}"
  end

  # Pagination is a filter change, not a reset: the current query string
  # round-trips so the Public switch, sport filters, search, and view all stay
  # put across pages. The link is assembled from the request path and query
  # string without `url_for`, because `url_for` treats reserved keys such as
  # `host`, `protocol` or `script_name` from the query string as URL options and
  # would echo them into the page. The result is escaped here because the pager
  # interpolates it into an attribute before marking the markup safe.
  def pagy_url_for(pagy, page)
    page_key = pagy.options[:page_key]
    query = request.query_parameters.to_h.except(page_key).merge(page_key => page)
    ERB::Util.html_escape("#{request.path}?#{query.to_query}")
  end
end
