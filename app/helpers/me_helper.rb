# frozen_string_literal: true

# Presentation helpers for the personal hub: the previous-period delta badges,
# the pulse hint and weekly details, and the JSON payloads handed to the chart
# controllers (the intensity pulse and the sport-mix pie).
module MeHelper
  DELTA_ICONS = { up: "trending-up", down: "trending-down", flat: "minus" }.freeze

  # Previous-window move beside a figure: an arrow glyph, the percentage, and
  # the full sentence for assistive technology. No badge when there is nothing
  # to compare against, so a first period is not dressed up as a drop.
  def comparison_badge(comparison)
    return if comparison.blank? || comparison[:direction] == :none

    direction = comparison[:direction]
    percent = comparison[:percent]
    visible = if direction == :flat || percent.nil?
      t("me.summary.comparison.flat_short")
    else
      "#{direction == :up ? '+' : '−'}#{number_to_percentage(percent.abs, precision: 0)}"
    end
    sentence = t("me.summary.comparison.#{direction}", percent: percent.nil? ? nil : number_to_percentage(percent.abs, precision: 0))

    tag.span(class: class_names("hub-delta", "hub-delta--#{direction}")) do
      safe_join([
        tag.i("", class: "ti ti-#{DELTA_ICONS.fetch(direction)}", aria: { hidden: true }),
        tag.span(visible, class: "hub-delta-value"),
        tag.span(sentence, class: "visually-hidden")
      ])
    end
  end

  def me_period_path(period, sport_id: @filter_sport&.id)
    me_path(period:, sport_id:)
  end

  # The pulse payload (DESIGN.md §15.1): one point per week with its X label,
  # its 0..100 score, whether it belongs to the selected period (the pink
  # highlight), whether it is a rest week, the week's facts already formatted
  # in the viewer's units and locale, and whether it is the period peak — so
  # the browser only draws and never formats. `older_url` is the previous
  # window the scroller fetches when it reaches the left edge.
  def pulse_chart_payload(intensity, period_range:, points:, older_url: nil)
    peak = intensity.peak(period_range)
    {
      granularity: "week",
      points: pulse_points(points, period_range, peak),
      older_url:,
      labels: {
        intensity: t("me.pulse.title"),
        in_period: t("me.pulse.in_period"),
        history: t("me.pulse.outside_period")
      }
    }
  end

  # A week's score as the tooltip and the table print it: a percentage for an
  # active week, the rest word otherwise.
  def pulse_score(row)
    row[:rest] ? t("me.pulse.rest") : number_to_percentage(row[:score], precision: 0)
  end

  # A week's facts in one line — activities, distance, ascent, time and, from
  # the second sport on, the sport count — for the tooltip, the peak sentence,
  # the values table and the keyboard announcement. A single sport is the
  # norm and stays unspoken.
  def pulse_detail(row)
    return t("me.pulse.rest") if row[:rest]

    facts = [
      t("me.pulse.workouts", count: row[:workouts]),
      format_distance(row[:distance], precision: 1),
      format_elevation(row[:ascent]),
      format_duration_human(row[:duration])
    ]
    facts << t("me.pulse.sports", count: row[:sports]) if row[:sports].to_i > 1
    facts.join(" · ")
  end

  # The pulse's explanation (DESIGN.md §15.1): the weekly grain over the whole
  # history, how a score is built, what the two ramps mean, the leftward
  # scroll, and the basis of the delta badges.
  def pulse_hint
    t("me.pulse.hint.#{@period}", range: pulse_history_range)
  end

  # "Semaine du 14 septembre", with the year when it is not the current one.
  def pulse_week_label(date)
    format = date.year == @today.year ? :day_month : :day_month_year
    t("me.pulse.week_of", date: I18n.l(date, format:))
  end

  # "semaine du 14 septembre" for the reading line, which prefixes "Pic :".
  def pulse_peak_label(row)
    format = row[:period].year == @today.year ? :day_month : :day_month_year
    t("me.pulse.peak_week", date: I18n.l(row[:period], format:))
  end

  # The workouts list filtered to that week, carrying the page-level sport
  # filter, exactly like a calendar day (DESIGN.md §15.3). The current week
  # stops at today rather than naming a future Sunday.
  def pulse_week_url(week_start)
    options = { period: "custom", from: week_start.iso8601, to: [ week_start + 6, @today ].min.iso8601 }
    options[:sports] = [ @filter_sport.id ] if @filter_sport
    workouts_path(options)
  end

  # A week holding one activity opens it directly; any other opens the list.
  def pulse_open_url(week_start)
    workout_id = @pulse_single_workouts&.[](week_start)
    workout_id ? workout_path(workout_id) : pulse_week_url(week_start)
  end

  def mix_value(metric, value)
    case metric.to_s
    when "distance" then format_distance(value)
    when "duration" then format_duration(value)
    when "workouts" then format_decimal(value.to_i)
    end
  end

  # Each sport slice carries the hub filtered to that sport over the same
  # period, the selected slice's way in (DESIGN.md §15.1); "Others" has none.
  def sport_mix_payload(mix)
    slices = mix[:slices].map do |slice|
      name = sport_display_name(slice[:sport])
      {
        name:,
        others: false,
        values: slice[:values],
        url: me_period_path(@period, sport_id: slice[:sport].id),
        open_label: t("me.mix.open", sport: name)
      }
    end
    if mix[:others]
      slices << { name: t("me.mix.others"), others: true, values: mix[:others][:values], url: nil, open_label: nil }
    end

    {
      labels: {
        distance: t("me.summary.distance"),
        duration: t("me.summary.duration"),
        workouts: t("me.summary.workouts")
      },
      slices:,
      total_label: t("me.mix.total"),
      unit_system: current_user.unit_system,
      locale: I18n.locale.to_s
    }
  end

  private

  def pulse_points(rows, period_range, peak)
    previous_year = nil
    rows.map do |row|
      date = row[:period]
      point = {
        label: pulse_axis_label(date, previous_year),
        tooltip_label: pulse_week_label(date),
        score: row[:score],
        score_label: pulse_score(row),
        rest: row[:rest],
        in_period: pulse_in_period?(date, period_range),
        detail: pulse_detail(row),
        url: row[:rest] ? nil : pulse_open_url(date),
        open_label: row[:rest] ? nil : t("me.pulse.open", count: row[:workouts]),
        peak: peak.present? && date == peak[:period]
      }
      previous_year = date.year
      point
    end
  end

  # The X category of a week: the short day/month, carrying the year on the
  # first week of each year so a multi-year scroll stays readable.
  def pulse_axis_label(date, previous_year)
    format = previous_year && previous_year == date.year ? :short : :short_year
    I18n.l(date, format:)
  end

  # A week belongs to the selected period when the two overlap: the period
  # rarely starts on a week start, and the week carrying its first days is
  # part of the highlighted span.
  def pulse_in_period?(week_start, period_range)
    return true if period_range.nil?

    week_start <= period_range.end && week_start + 6 >= period_range.begin
  end

  # The all-history span named by the hint, so the reader knows what the
  # waveform covers regardless of the selected period.
  def pulse_history_range
    return if @pulse_rows.blank?

    from = @pulse_rows.first[:period]
    if @pulse_rows.length == 1
      t("me.pulse.hint.range.week_single", date: I18n.l(from, format: :day_month_year))
    else
      t("me.pulse.hint.range.week", start: I18n.l(from, format: :day_month_year))
    end
  end
end
