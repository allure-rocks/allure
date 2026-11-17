# frozen_string_literal: true

# The owner's personal hub: a page-level sport filter, the period figures with
# previous-period deltas and the intensity pulse, the adaptive activity
# calendar, the sport mix, regularity statistics, recent segment efforts, the
# latest records and the recent workouts. Everything is computed from the
# viewer-timezoned buckets produced by Stats::Aggregates; the figures and the
# comparisons read the same zero-filled series that feeds the pulse, so the
# numbers, the labels and the waveform can never disagree. The pulse itself is
# one weekly waveform over the whole history: the selected period only moves
# the pink highlight, and older windows are fetched from #pulse as the viewer
# scrolls back.
#
# Periods are meaningful calendar windows, not rolling SQL offsets: "Cette
# semaine" runs from the user's week start to today, "Cette année" from
# January 1st, and only "30 derniers jours" is rolling. The previous window
# used for the deltas mirrors each semantic (previous calendar week, previous
# 30 days, same elapsed period last year).
class MeController < ApplicationController
  TRENDS = Allure::Stats::Trends

  PERIODS = [ *Allure::Stats::Periods::KEYS, "all" ].freeze
  DEFAULT_PERIOD = "days30"
  ACTIVE_DAYS_WINDOW = 84
  YEAR_DAY_WINDOW = 730
  TREND_WEEKS = 12
  PULSE_CHUNK_WEEKS = 104
  MIX_SPORTS = 5
  RECORD_LIMIT = 3
  SEGMENT_LIMIT = 5
  RECENT_LIMIT = 12
  TRAINING_LOAD_DAYS = 90

  SUMMARY_COLUMNS = [
    Arel.sql("COUNT(*)"),
    Arel.sql("COALESCE(SUM(distance), 0)"),
    Arel.sql("COALESCE(SUM(ascent), 0)"),
    Arel.sql("COALESCE(SUM(moving_time), 0)")
  ].freeze

  def show
    @period = PERIODS.include?(params[:period]) ? params[:period] : DEFAULT_PERIOD
    @filter_sport = find_filter_sport
    @practiced_sports = practiced_sports
    @today = viewer_today
    @week_start = current_week_start
    @workouts_count = current_user.workouts.count
    @has_workouts = @workouts_count.positive?

    @summary = summary
    @comparison = comparison
    @pulse_period = period_range
    @pulse_rows = pulse_weeks
    @intensity = Allure::Stats::Intensity.new(@pulse_rows)
    @pulse_points = pulse_chunk
    @pulse_older_url = pulse_older_url(@pulse_points)
    @selector_sports = selector_sports
    @sport_mix = sport_mix
    @regularity = regularity
    @week = week_to_date
    @latest_records = latest_records
    @recent_segments = recent_segments
    @recent_workouts = recent_workouts
    @training_load = training_load
  end

  # Older windows of the weekly waveform, fetched by the pulse scroller as it
  # reaches the left edge. Owner-scoped and read-only; each chunk is scored
  # against the same whole-history basis as the page, so the shape already on
  # screen never changes (DESIGN.md §15.1).
  def pulse
    @period = PERIODS.include?(params[:period]) ? params[:period] : DEFAULT_PERIOD
    @filter_sport = find_filter_sport
    @today = viewer_today
    before = pulse_before_param
    return head :bad_request if before == :invalid

    @pulse_period = period_range
    @pulse_rows = pulse_weeks
    @intensity = Allure::Stats::Intensity.new(@pulse_rows)
    chunk = pulse_chunk(before:)

    render json: helpers.pulse_chart_payload(
      @intensity,
      period_range: @pulse_period,
      points: chunk,
      older_url: pulse_older_url(chunk)
    )
  end

  private

  def find_filter_sport
    return nil if params[:sport_id].blank?

    sport = Sport.find_by(id: params[:sport_id])
    return nil unless sport && current_user.workouts.exists?(sport_id: sport.id)

    sport
  end

  def practiced_sports
    Sport.catalog_order.where(id: current_user.workouts.select(:sport_id)).to_a
  end

  def current_week_start
    @week_start ||= TRENDS.week_start_on_or_before(@today, current_user.week_start)
  end

  def filtered_workouts
    return current_user.workouts unless @filter_sport

    current_user.workouts.where(sport_id: @filter_sport.id)
  end

  # Inclusive date range of the selected period, or nil for "Tout", and the
  # window the deltas compare against. Both come from the shared calendar
  # windows so the list's period filter and the hub agree.
  def period_range
    Allure::Stats::Periods.range(@period, today: @today, week_start: current_user.week_start)
  end

  def previous_period_range
    Allure::Stats::Periods.previous_range(@period, today: @today, week_start: current_user.week_start)
  end

  def day_rows
    @day_rows ||= TRENDS.new(buckets_for(:day)).series(
      periods: @period == "year" ? YEAR_DAY_WINDOW : ACTIVE_DAYS_WINDOW,
      ending_on: @today,
      granularity: :day
    )
  end

  def current_rows
    @current_rows ||= TRENDS.between(day_rows, period_range)
  end

  # The weekly waveform spans the whole history, independent of the selected
  # period: the period only moves the highlight, so the shape never changes
  # when the viewer switches windows. Unlike every other window this scan is
  # unbounded — the all-time pulse must not drop workouts behind the
  # recent-2000 cap.
  def pulse_weeks
    @pulse_weeks ||= begin
      buckets = Stats::Aggregates.new(user: current_user).by_time(
        granularity: :week,
        sport_id: @filter_sport&.id,
        limit: nil
      )
      @pulse_single_workouts = single_workouts(buckets)
      if buckets.empty?
        []
      else
        TRENDS.new(buckets).series(
          periods: [ ((current_week_start - buckets.first[:period]).to_i / 7) + 1, 1 ].max,
          ending_on: current_week_start,
          granularity: :week
        )
      end
    end
  end

  # Week start => the short id of its one workout, for the weeks holding a
  # single activity: their button opens that activity, not a one-row list.
  def single_workouts(buckets)
    buckets.group_by { |bucket| bucket[:period] }.filter_map do |period, rows|
      next unless rows.sum { |row| row[:total_workouts] } == 1

      [ period, rows.first[:workout_id] ] if rows.first[:workout_id]
    end.to_h
  end

  # The most recent slice of the scored waveform the page renders; older
  # slices are fetched one at a time from #pulse. Slicing the scored rows and
  # not the raw buckets is what keeps the already-drawn shape stable across
  # chunks.
  def pulse_chunk(before: nil)
    rows = before ? @intensity.rows.take_while { |row| row[:period] < before } : @intensity.rows
    rows.last(PULSE_CHUNK_WEEKS)
  end

  # The URL of the next older slice, or nil once the first activity is
  # rendered. Every chunk is scored against the same whole-history basis, so
  # the URL carries the period and the sport filter but no scoring state.
  def pulse_older_url(chunk)
    return nil if chunk.empty?
    return nil unless @intensity.rows.any? { |row| row[:period] < chunk.first[:period] }

    pulse_me_path(period: @period, before: chunk.first[:period].iso8601, sport_id: @filter_sport&.id)
  end

  def pulse_before_param
    return nil if params[:before].blank?

    Date.iso8601(params[:before].to_s)
  rescue Date::Error, ArgumentError
    :invalid
  end

  def summary
    return summary_from_sql if @period == "all"

    TRENDS.totals(current_rows)
  end

  def summary_from_sql
    workouts, distance, ascent, duration = filtered_workouts.pick(*SUMMARY_COLUMNS)
    { workouts: workouts.to_i, distance: distance.to_f, ascent: ascent.to_f, duration: duration.to_i }
  end

  def comparison
    range = previous_period_range
    return nil if range.nil?

    previous = TRENDS.totals(TRENDS.between(day_rows, range))
    current = @summary
    TRENDS::METRICS.to_h do |metric|
      [ metric, TRENDS.compare(current: current.fetch(metric), previous: previous.fetch(metric)) ]
    end
  end

  # The sports practised on the period, most active first, each with its
  # period count, plus the active filter even when it has none there
  # (DESIGN.md §8.4). The ranking always reads the unfiltered buckets: a
  # filtered page still shows the other sports so the filter can be changed
  # in one tap.
  def selector_sports
    counts = @period == "all" ? current_user.workouts.group(:sport_id).count : sport_counts
    @practiced_sports.each_with_index
      .select { |sport, _index| counts.fetch(sport.id, 0).to_i.positive? || @filter_sport&.id == sport.id }
      .sort_by { |sport, index| [ -counts.fetch(sport.id, 0).to_i, index ] }
      .map { |sport, _index| { sport:, count: counts.fetch(sport.id, 0).to_i, active: @filter_sport&.id == sport.id } }
  end

  def sport_counts
    rows = @filter_sport ? unfiltered_current_rows : current_rows
    TRENDS.sport_totals(rows).transform_values { |values| values[:workouts] }
  end

  def unfiltered_current_rows
    @unfiltered_current_rows ||= TRENDS.between(
      TRENDS.new(unfiltered_buckets_for(:day)).series(
        periods: @period == "year" ? YEAR_DAY_WINDOW : ACTIVE_DAYS_WINDOW,
        ending_on: @today,
        granularity: :day
      ),
      period_range
    )
  end

  # The sport mix is only meaningful for more than one sport and only while
  # no sport filter is active; the regularity card then spans the row alone.
  def sport_mix
    return nil if @filter_sport || !@has_workouts

    totals = @period == "all" ? all_time_sport_values : TRENDS.sport_totals(current_rows)
    return nil if totals.size < 2

    ranked = totals.sort_by { |_sport_id, values| -values[:distance] }.first(MIX_SPORTS)
    others = totals.except(*ranked.map(&:first))
    sports = Sport.where(id: ranked.map(&:first)).index_by(&:id)
    slices = ranked.filter_map do |sport_id, values|
      sport = sports[sport_id]
      { sport:, values: } if sport
    end
    return nil if slices.empty?

    { slices:, others: others.present? ? { values: sum_values(others.values) } : nil }
  end

  def sum_values(list)
    list.reduce({ workouts: 0, distance: 0.0, duration: 0, ascent: 0.0 }) do |sum, values|
      sum[:workouts] += values[:workouts]
      sum[:distance] += values[:distance]
      sum[:duration] += values[:duration]
      sum[:ascent] += values[:ascent]
      sum
    end
  end

  # "Tout" has no bounded series to read; the all-time mix comes from one
  # grouped query. Every other period reads the viewer-timezoned buckets.
  def all_time_sport_values
    current_user.workouts.group(:sport_id).pluck(
      :sport_id,
      Arel.sql("COUNT(*)"),
      Arel.sql("COALESCE(SUM(distance), 0)"),
      Arel.sql("COALESCE(SUM(moving_time), 0)"),
      Arel.sql("COALESCE(SUM(ascent), 0)")
    ).to_h do |sport_id, workouts, distance, duration, ascent|
      [ sport_id, { workouts: workouts.to_i, distance: distance.to_f, duration: duration.to_i, ascent: ascent.to_f } ]
    end
  end

  def regularity
    weekly = TRENDS.new(buckets_for(:week))
    active = TRENDS.new(buckets_for(:day)).active_days(window: ACTIVE_DAYS_WINDOW, today: @today)
    weekly.streaks(week_start: current_user.week_start, today: @today).merge(
      active_days: active[:count],
      active_window: active[:window],
      best_week: weekly_series.max_by { |row| row[:distance] }
    )
  end

  def week_to_date
    TRENDS.new(buckets_for(:week)).week_to_date(week_start: current_user.week_start, today: @today)
  end

  def weekly_series
    @weekly_series ||= TRENDS.new(buckets_for(:week)).series(
      periods: TREND_WEEKS, ending_on: current_week_start, granularity: :week
    )
  end

  def buckets_for(granularity)
    @buckets ||= {}
    @buckets[granularity] ||= Stats::Aggregates.new(user: current_user).by_time(granularity:, sport_id: @filter_sport&.id)
  end

  def unfiltered_buckets_for(granularity)
    @unfiltered_buckets ||= {}
    @unfiltered_buckets[granularity] ||= Stats::Aggregates.new(user: current_user).by_time(granularity:)
  end

  # The most recently set records, classic types and best-effort distances
  # together, newest workout first. Types the sport cannot express are hidden
  # exactly as on /me/records.
  def latest_records
    records = current_user.records
    efforts = current_user.effort_records
    if @filter_sport
      records = records.where(sport_id: @filter_sport.id)
      efforts = efforts.where(sport_id: @filter_sport.id)
    end
    records = records.includes(:sport, :workout).order(workout_started_at: :desc, id: :desc).to_a
      .select { |record| Record.visible_type?(record.record_type, record.sport) }
    efforts = efforts.includes(:sport, :workout).order(workout_started_at: :desc, id: :desc).limit(RECORD_LIMIT).to_a
    (records.first(RECORD_LIMIT) + efforts).max_by(RECORD_LIMIT, &:workout_started_at)
  end

  # The latest efforts on every local course the viewer ran; a rank is only
  # meaningful for a personal best on a leaderboarded segment, so the standing
  # lookup is limited to those rows.
  def recent_segments
    scope = current_user.segment_efforts.includes(segment: :sport)
    scope = scope.where(sport_id: @filter_sport.id) if @filter_sport
    efforts = scope.order(started_at: :desc, id: :desc).limit(SEGMENT_LIMIT).to_a
    return [] if efforts.empty?

    personal = personal_rankings_for(efforts)
    standings = standings_for(efforts, personal)
    efforts.map do |effort|
      key = [ effort.segment_id, effort.sport_id ]
      ranking = personal.fetch(key)
      {
        effort:, segment: effort.segment, standing: standings[key],
        personal_rank: ranking.index(effort.id) + 1, personal_total: ranking.size
      }
    end
  end

  # The viewer's own efforts per (segment, sport) the listed efforts belong to,
  # fastest first, so each row can say where it stands among the viewer's own
  # attempts — distinct from the leaderboard standing, which ranks athletes.
  def personal_rankings_for(efforts)
    current_user.segment_efforts
      .where(segment_id: efforts.map(&:segment_id).uniq)
      .order(:elapsed_time, :started_at, :id)
      .pluck(:segment_id, :sport_id, :id)
      .group_by { |segment_id, sport_id, _id| [ segment_id, sport_id ] }
      .transform_values { |rows| rows.map(&:last) }
  end

  def standings_for(efforts, personal)
    segments = efforts.filter_map do |effort|
      segment = effort.segment
      best = personal.fetch([ effort.segment_id, effort.sport_id ]).first == effort.id
      segment if best && segment.kind == "segment" && segment.viewable_by?(current_user)
    end.uniq
    return {} if segments.empty?

    Segments::Standings.new(segments:, viewer: current_user).call.index_by { |row| [ row.segment.id, row.sport.id ] }
  end

  # The training-load card (docs/dev/HEART-RATE.md): nil until a recording
  # carries usable heart rate; without a profile, only the invitation to set
  # one. The load covers every sport, whatever the page filter.
  def training_load
    history = HeartRates::History.new(user: current_user)
    return nil unless history.any?
    return { profile: false } unless history.zones?

    model = Allure::Stats::TrainingLoad.new(history.daily_loads, through: @today)
    return nil if model.empty?

    days = model.last(TRAINING_LOAD_DAYS)
    from = @today - (TRAINING_LOAD_DAYS - 1)
    warmup_until = model.days.first.date + (Allure::Stats::TrainingLoad::FITNESS_DAYS - 1)
    {
      profile: true,
      today: model.today,
      days:,
      warmup_until: (warmup_until if warmup_until >= @today - (TRAINING_LOAD_DAYS - 1)),
      warming_up: warmup_until >= @today,
      without: history.workouts_without_heart_rate(from:, to: @today),
      partial: history.partial_workouts(from:, to: @today)
    }
  end

  def recent_workouts
    scope = current_user.workouts
    scope = scope.where(sport_id: @filter_sport.id) if @filter_sport
    scope.includes(:sport, :active_publications, :scheduled_publications, :records, :effort_records,
                   :credited_by, :credited_from, participant_links: { workout: :user },
                   workout_participations: { participant_actor: :user },
                   route_image_attachment: :blob)
      .order(started_at: :desc, id: :desc).limit(RECENT_LIMIT).to_a
  end
end
