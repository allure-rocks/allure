# frozen_string_literal: true

# Presentation of the analyzer's flagged readings (docs/dev/WORKOUT.md,
# DESIGN.md §15.5). Owner-only: every caller renders them for the workout's
# owner and never from a publication.
module WorkoutAnomaliesHelper
  ANOMALY_ICONS = {
    "gps" => "gps",
    "time" => "clock-exclamation",
    "heart_rate" => "heart-off",
    "elevation" => "mountain",
    "power" => "bolt",
    "cadence" => "rotate-clockwise"
  }.freeze

  # The families drawn on the map: only those about positions and timing.
  MAP_ANOMALY_FAMILIES = %w[gps time].freeze

  # One presented row per stored finding, in route order. `tier` is `major`
  # (it changes a figure), `minor`, or `signature` (a minor kind this device
  # shows on most of the owner's recordings, explained once instead).
  def workout_anomalies(workout, signatures: Workouts::AnomalySignatures.new(workout:).kinds)
    workout.anomaly_findings.filter_map do |finding|
      kind = finding["kind"].to_s
      next unless Allure::Gpx::Anomalies::KINDS.key?(kind)

      family = Allure::Gpx::Anomalies.family_of(kind)
      tier = finding["tier"] == "major" ? "major" : "minor"
      tier = "signature" if tier == "minor" && signatures.include?(kind)
      {
        kind:,
        family:,
        tier:,
        icon: ANOMALY_ICONS.fetch(family),
        title: t("workouts.anomalies.kinds.#{kind}"),
        detail: anomaly_detail(kind, finding["detail"] || {}, sport: workout.sport),
        start_distance: finding["start_distance"].to_f,
        end_distance: finding["end_distance"].to_f,
        start_time: finding["start_time"].to_i,
        coordinates: finding["coordinates"],
        path: finding["path"]
      }
    end
  end

  # The anomalies tab groups by kind, in the stored kind order, with the total
  # count of each kind (a kind may hold more findings than are stored). The
  # kinds holding a figure-changing finding come first.
  def workout_anomaly_groups(workout, anomalies)
    counts = workout.data_anomalies.fetch("counts", {})
    order = Allure::Gpx::Anomalies::KINDS.keys
    anomalies.group_by { |anomaly| anomaly[:kind] }
             .map { |kind, rows| { kind:, rows:, total: counts.fetch(kind, rows.length), major: rows.any? { |row| row[:tier] == "major" } } }
             .sort_by { |group| [ group[:major] ? 0 : 1, order.index(group[:kind]) ] }
  end

  # The flagged findings the tab counts: the device's ordinary behaviour is
  # explained apart.
  def anomaly_flagged_count(workout, anomalies)
    counts = workout.data_anomalies.fetch("counts", {})
    anomalies.reject { |anomaly| anomaly[:tier] == "signature" }.map { |anomaly| anomaly[:kind] }.uniq
             .sum { |kind| counts.fetch(kind, 0) }
  end

  # Chart payload: every flagged finding, as a range with its translated label
  # and tier; the major ones show by default, the others while inspecting.
  def anomaly_chart_payload(anomalies)
    anomalies.filter_map do |anomaly|
      next if anomaly[:tier] == "signature"

      {
        "start" => anomaly[:start_distance],
        "end" => anomaly[:end_distance],
        "family" => anomaly[:family],
        "tier" => anomaly[:tier],
        "label" => anomaly_label(anomaly)
      }
    end
  end

  # Map payload: the position and timing findings, with the rejected
  # positions' own coordinates.
  def anomaly_map_payload(anomalies)
    anomalies.filter_map do |anomaly|
      next unless MAP_ANOMALY_FAMILIES.include?(anomaly[:family])
      next if anomaly[:tier] == "signature"

      payload = {
        "start" => anomaly[:start_distance],
        "end" => anomaly[:end_distance],
        "tier" => anomaly[:tier],
        "label" => anomaly_label(anomaly)
      }
      if anomaly[:coordinates].present?
        payload["coordinates"] = anomaly[:coordinates]
        payload["path"] = anomaly[:path] if anomaly[:path].present?
      end
      payload
    end
  end

  # A finding at one point (a rejected first fix, a single spike) still
  # previews a visible slice: at least `ANOMALY_MIN_RANGE_METRES` around it.
  ANOMALY_MIN_RANGE_METRES = 40.0

  def anomaly_row_range(anomaly)
    first = anomaly[:start_distance]
    last = anomaly[:end_distance]
    return [ first, last ] if last - first >= ANOMALY_MIN_RANGE_METRES

    middle = (first + last) / 2.0
    low = [ middle - (ANOMALY_MIN_RANGE_METRES / 2.0), 0.0 ].max
    [ low.round(1), (low + ANOMALY_MIN_RANGE_METRES).round(1) ]
  end

  # The figures an anomaly makes wrong, keyed by the summary metric they
  # annotate: the plausible value, why, and where (docs/dev/WORKOUT.md).
  def workout_anomaly_notes(workout)
    impact = workout.data_anomalies.fetch("impact", {})
    contested = Array(workout.contested_metrics)
    notes = {}
    if (speed = impact["max_speed"])
      reason = t("workouts.anomalies.notes.reasons.#{speed['basis'] == 'device' ? 'device' : 'track'}")
      range = [ speed["start_distance"], speed["end_distance"] ]
      notes[:max_speed] = anomaly_note(format_speed(speed["plausible"].to_f), reason, range, contested.include?("max_speed"))
      if speed["plausible"].to_f.positive?
        pace = format_pace(1000.0 / speed["plausible"].to_f, sport: workout.sport)
        notes[:best_pace] = anomaly_note(pace, reason, range, contested.include?("best_pace"))
      end
    end
    if (distance = impact["distance"])
      notes[:distance] = anomaly_note(format_distance(distance["plausible"].to_f), t("workouts.anomalies.notes.reasons.track"),
                                      nil, contested.include?("distance"))
    end
    if (heart_rate = impact["max_heart_rate"])
      notes[:max_heart_rate] = anomaly_note(metric_with_unit(heart_rate["plausible"], t("units.heart_rate.bpm")),
                                            t("workouts.anomalies.notes.reasons.heart_rate"),
                                            [ heart_rate["start_distance"], heart_rate["end_distance"] ], false)
    end
    if (ascent = impact["ascent"])
      # The descent rests on the same readings: shown the same way, but no
      # record reads it, so it is never contested.
      notes[:ascent] = elevation_mismatch_note(ascent, contested.include?("ascent"))
      notes[:descent] = elevation_mismatch_note(ascent, false)
    end
    notes
  end

  # The impact rows the tab lists first, in summary order.
  def workout_anomaly_impacts(workout)
    notes = workout_anomaly_notes(workout)
    %i[distance max_speed max_heart_rate ascent descent].filter_map do |key|
      next unless notes[key]

      notes[key].merge(key:, label: t("workouts.show.metrics.#{key}"))
    end
  end

  def anomaly_label(anomaly) = [ anomaly[:title], anomaly[:detail] ].compact_blank.join(" · ")

  def anomaly_detail(kind, detail, sport:)
    count = detail["count"].to_i
    text = case kind
    when "gps_rejected"
      t("workouts.anomalies.details.gps_rejected", count: detail["value"].to_i)
    when "gps_jump"
      t("workouts.anomalies.details.gps_jump", speed: anomaly_speed(detail["speed"]),
                                               distance: format_distance(detail["metres"].to_f))
    when "speed_implausible"
      t("workouts.anomalies.details.speed_implausible", speed: anomaly_speed(detail["speed"]))
    when "timestamp_skew"
      t("workouts.anomalies.details.timestamp_skew", speed: anomaly_speed(detail["speed"]),
                                                     corrected: anomaly_speed(detail["corrected"]))
    when "recording_gap"
      t("workouts.anomalies.details.recording_gap", duration: format_duration(detail["seconds"]),
                                                    distance: format_distance(detail["metres"].to_f))
    when "hr_missing"
      t("workouts.anomalies.details.hr_missing.#{detail['position'].presence_in(%w[start end]) || 'middle'}",
        duration: format_duration(detail["seconds"]))
    when "hr_frozen"
      t("workouts.anomalies.details.hr_frozen", bpm: detail["bpm"], frozen: format_duration(detail["frozen"]),
                                                missing: format_duration(detail["missing"]))
    when "hr_jump"
      t("workouts.anomalies.details.hr_jump", from: detail["from"], to: detail["to"], seconds: detail["seconds"])
    when "hr_out_of_range"
      t("workouts.anomalies.details.hr_out_of_range", bpm: detail["bpm"])
    when "elevation_step"
      t("workouts.anomalies.details.elevation_step", delta: format_elevation(detail["metres"].to_f.abs),
                                                     direction: t("workouts.anomalies.directions.#{detail['metres'].to_f.negative? ? 'down' : 'up'}"),
                                                     seconds: detail["seconds"])
    when "elevation_mismatch"
      t("workouts.anomalies.details.elevation_mismatch.#{detail['value'].to_f.negative? ? 'lower' : 'higher'}",
        delta: format_elevation(detail["value"].to_f.abs), time: format_duration(detail["first_time"]))
    when "power_spike"
      t("workouts.anomalies.details.power_spike", power: format_power(detail["reading"]))
    when "cadence_spike"
      t("workouts.anomalies.details.cadence_spike", cadence: format_decimal(detail["reading"]),
                                                    unit: sport&.cadence_unit.presence || "rpm")
    end
    count > 1 && kind != "gps_rejected" ? t("workouts.anomalies.details.repeated", detail: text, count:) : text
  end

  private

  def anomaly_note(value, reason, range, excluded)
    text = t("workouts.anomalies.notes.plausible", value:, reason:)
    text = [ text, t("workouts.anomalies.notes.excluded") ].join(" · ") if excluded
    range = range&.map(&:to_f)
    { text:, range: (range && range.last >= range.first ? anomaly_row_range({ start_distance: range.first, end_distance: range.last }) : nil) }
  end

  # An elevation gap has no plausible value to name: the recorded profile is
  # the only one there is (docs/dev/WORKOUT.md).
  def elevation_mismatch_note(impact, excluded)
    text = t("workouts.anomalies.notes.elevation_mismatch", gap: format_elevation(impact["gap"].to_f))
    text = [ text, t("workouts.anomalies.notes.excluded_metric") ].join(" · ") if excluded
    { text:, range: anomaly_row_range({ start_distance: impact["start_distance"].to_f, end_distance: impact["end_distance"].to_f }) }
  end

  def anomaly_speed(kmh) = format_speed(kmh.to_f / 3.6)
end
