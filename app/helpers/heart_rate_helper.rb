# frozen_string_literal: true

# Presentation of the owner's heart-rate zones (docs/dev/HEART-RATE.md,
# DESIGN.md §10.21). Owner-only surfaces.
module HeartRateHelper
  HEART_RATE_ANOMALY_KINDS = %w[hr_frozen hr_jump hr_missing hr_out_of_range].freeze

  def heart_rate_zone_name(number)
    t("heart_rate.zones.names.#{Allure::HeartRate::Zones::NAMES.fetch(number - 1)}")
  end

  def heart_rate_zone_description(number)
    t("heart_rate.zones.descriptions.#{Allure::HeartRate::Zones::NAMES.fetch(number - 1)}")
  end

  # « < 114 bpm », « 114–132 bpm », « ≥ 171 bpm ».
  def heart_rate_zone_range(lower, upper)
    unit = t("units.heart_rate.bpm")
    if lower.nil?
      t("heart_rate.zones.range.below", bpm: upper + 1, unit:)
    elsif upper.nil?
      t("heart_rate.zones.range.above", bpm: lower, unit:)
    else
      t("heart_rate.zones.range.between", lower:, upper:, unit:)
    end
  end

  # One row per zone: number, name, range, seconds and share (0..100).
  def heart_rate_zone_rows(zones, seconds = nil)
    total = Array(seconds).sum
    zones.ranges.each_with_index.map do |(lower, upper), index|
      value = seconds&.fetch(index)
      {
        number: index + 1,
        name: heart_rate_zone_name(index + 1),
        range: heart_rate_zone_range(lower, upper),
        seconds: value,
        share: total.positive? && value ? value * 100.0 / total : 0.0
      }
    end
  end

  # « Le temps sous 95 bpm (50 % de votre fréquence maximale) … ».
  def heart_rate_load_floor_sentence(zones)
    t("heart_rate.load_floor.#{zones.basis}", bpm: zones.load_floor, percent: zones.load_floor_percent)
  end

  # « Zones en % de votre fréquence maximale (190 bpm). »
  def heart_rate_basis_sentence(zones)
    t("heart_rate.zones.basis.#{zones.basis}", max: zones.max, rest: zones.rest)
  end

  # The templates the settings page's live preview fills in
  # (heart_rate_zones_preview_controller.js), with the same rounding as
  # Allure::HeartRate::Zones.
  def heart_rate_zone_preview_formats
    {
      unit: t("units.heart_rate.bpm"),
      below: I18n.t("heart_rate.zones.range.below"),
      above: I18n.t("heart_rate.zones.range.above"),
      between: I18n.t("heart_rate.zones.range.between"),
      floor: Allure::HeartRate::Zones::BASES.to_h { [ it, I18n.t("heart_rate.load_floor.#{it}") ] },
      floor_offset: Allure::HeartRate::Zones::LOAD_FLOOR_OFFSET
    }
  end

  # The owner's zone reading of a recording, or nil
  # (docs/dev/HEART-RATE.md): nil without a profile or a histogram. A histogram too thin to
  # slice gives a state that says why (`:sparse`, `:partial`) instead of a
  # tab that silently disappears. Never for a credit row or a manual entry,
  # which hold no histogram.
  def workout_heart_rate_zones(workout)
    @workout_heart_rate_zones ||= {}
    return @workout_heart_rate_zones[workout.id] if @workout_heart_rate_zones.key?(workout.id)

    @workout_heart_rate_zones[workout.id] = begin
      row = workout.recording? ? workout.heart_rate : nil
      zones = workout.user.heart_rate_zones if row
      heart_rate_zone_reading(workout, row, zones) if zones
    end
  end

  # The training-load chart payload (docs/dev/HEART-RATE.md): one point per
  # day with the figures rounded for display and the day already formatted,
  # and the last day of the warm-up when it falls in the window.
  def training_load_payload(days, warmup_until: nil)
    {
      series: {
        fitness: t("me.training_load.fitness"),
        fatigue: t("me.training_load.fatigue"),
        form: t("me.training_load.form"),
        load: t("me.training_load.load")
      },
      warmup_until: (warmup_until.iso8601 if warmup_until && days.any? && warmup_until >= days.first.date),
      points: days.map do |day|
        {
          x: day.date.iso8601,
          label: l(day.date, format: :day_month_year),
          load: day.load.round,
          fitness: day.fitness.round(1),
          fatigue: day.fatigue.round(1),
          form: day.form.round(1)
        }
      end
    }
  end

  # The table equivalent: one row per calendar week of the account (its week
  # start), newest first, with the week's summed load and the figures of its
  # last day; a week the window cuts or today has not finished is marked.
  def training_load_weeks(days, today:)
    days.group_by { Allure::Stats::Trends.week_start_on_or_before(it.date, current_user.week_start) }.map do |start, week|
      state = if week.length == 7 then nil elsif week.last.date == today then :current else :partial end
      { start:, load: week.sum(&:load), day: week.last, state: }
    end.reverse
  end

  def training_load_week_label(week)
    label = t("me.training_load.week_of", date: l(week[:start], format: :day_month_year))
    week[:state] ? "#{label} #{t("me.training_load.week_states.#{week[:state]}")}" : label
  end

  def training_load_figure(value) = number_with_delimiter(value.round)

  def training_load_form(value)
    rounded = value.round
    rounded.positive? ? "+#{rounded}" : rounded.to_s.sub("-", "−")
  end

  # The statistics rows: one per period, oldest first, labelled for the
  # granularity.
  def zone_distribution_rows(periods, granularity)
    periods.map do |period|
      if granularity == "week"
        axis = l(period[:period], format: :short)
        label = t("stats.heart_rate.week_of", date: axis)
      else
        axis = label = format_stat_period(period[:period], "month")
      end
      { label:, axis:, seconds: period[:seconds] }
    end
  end

  def zone_distribution_payload(rows, scale: "time")
    {
      scale:,
      zones: (1..Allure::HeartRate::Zones::COUNT).map { |zone| "Z#{zone} · #{heart_rate_zone_name(zone)}" },
      periods: rows.map do |row|
        total = row[:seconds].sum
        shares = row[:seconds].map { total.positive? ? (it * 100.0 / total).round(1) : 0 }
        row.merge(time: row[:seconds].map { format_duration(it) }, shares:)
      end
    }
  end

  # One zone's cell on the zone page: its time, or its share of the period
  # under the `share` scale; a dash without time.
  def zone_distribution_value(seconds, total, scale)
    return "—" if seconds.zero?

    scale == "share" ? number_to_percentage(seconds * 100.0 / total, precision: 0) : format_duration(seconds)
  end

  # Low (Z1–Z2), moderate (Z3) and high (Z4–Z5) shares of the window's time,
  # in percent, or nil without time.
  def zone_intensity_split(periods)
    totals = periods.each_with_object(Array.new(Allure::HeartRate::Zones::COUNT, 0)) do |period, sums|
      period[:seconds].each_with_index { |seconds, index| sums[index] += seconds }
    end
    total = totals.sum
    return nil unless total.positive?

    {
      low: (totals[0] + totals[1]) * 100.0 / total,
      moderate: totals[2] * 100.0 / total,
      high: (totals[3] + totals[4]) * 100.0 / total
    }
  end

  # A zone row previews every stretch of that zone on the profile and the map
  # (workout-tabs): the first start and last end keep the single-range
  # contract, the list carries the stretches.
  def heart_rate_zone_row_attributes(row)
    ranges = Array(row[:ranges])
    return {} if ranges.empty?

    attributes = analysis_row_attributes(ranges.first[0], ranges.last[1], source: "heart_rate_zone",
                                                                          label: "Z#{row[:number]} · #{row[:name]}")
    attributes[:data][:analysis_ranges] = ranges.to_json
    attributes
  end

  def heart_rate_zone_share(share)
    number_to_percentage(share, precision: 0)
  end

  private

  def heart_rate_zone_reading(workout, row, zones)
    reading = { state: :usable, zones:, coverage: row.coverage, rows: [], seconds: nil, load: nil,
                below_floor: 0, frozen_seconds: row.frozen_seconds,
                anomalies: (workout.data_anomalies.to_h["counts"] || {}).keys.intersect?(HEART_RATE_ANOMALY_KINDS) }
    reason = row.unusable_reason
    return reading.merge(state: reason) if reason
    return nil unless row.usable?

    seconds = row.zone_seconds_for(zones)
    rows = heart_rate_zone_rows(zones, seconds)
    # Where each zone was ridden, for the profile and the map; a
    # duration-only session has no distance to place it on.
    if workout.distance.to_f.positive?
      ranges = Allure::HeartRate::ZoneRanges.compute(workout.track_segments.sort_by(&:position), zones)
      rows.each { it[:ranges] = ranges.fetch(it[:number]) }
    end
    reading.merge(seconds:, rows:, load: row.load_for(zones), below_floor: zones.below_floor_seconds(row.histogram))
  end
end
