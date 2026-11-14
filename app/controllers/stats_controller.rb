# frozen_string_literal: true

# The current user's workout aggregates. Owner-only throughout (no :id
# route, so another user's stats are never addressable). Each action serves
# HTML (server-rendered tables) and JSON (chart/calendar datasets) from the
# same aggregates; JSON carries `Cache-Control: private, no-store`.
class StatsController < ApplicationController
  # Stats hub (M4 Slice 0): landing page for the by_time / by_sport datasets.
  def show; end

  def by_time
    granularity = params[:time].presence || "month"
    sport = find_sport_if_requested

    buckets = Stats::Aggregates.new(user: current_user).by_time(granularity:, sport_id: sport&.id)
    @buckets_by_sport = group_for_tables(buckets)
    @granularity = granularity

    respond_to do |format|
      format.html
      format.json do
        response.headers["Cache-Control"] = "private, no-store"
        render json: { buckets: buckets }
      end
    end
  rescue ArgumentError
    raise ActiveRecord::RecordNotFound
  end

  def by_sport
    sport = find_sport_if_requested

    rows = Stats::Aggregates.new(user: current_user).by_sport(sport_id: sport&.id)
    @rows_by_sport = group_for_tables(rows)

    respond_to do |format|
      format.html
      format.json do
        response.headers["Cache-Control"] = "private, no-store"
        render json: { sports: rows }
      end
    end
  end

  # Time in each heart-rate zone per week (last 26) or month (last 24), for
  # every sport or one (PLAN_HEART_RATE.md §4). HTML only: the chart payload
  # is embedded and the table below it is its text equivalent.
  HEART_RATE_WINDOWS = { "week" => 26, "month" => 24 }.freeze
  HEART_RATE_SCALES = %w[time share].freeze

  def heart_rate
    @granularity = HEART_RATE_WINDOWS.key?(params[:time]) ? params[:time] : "week"
    @scale = HEART_RATE_SCALES.include?(params[:scale]) ? params[:scale] : "time"
    @zones = current_user.heart_rate_zones
    @sports = Sport.catalog_order.where(id: current_user.workouts.recordings.joins(:heart_rate).select(:sport_id)).to_a
    @sport = @sports.find { it.id.to_s == params[:sport_id].to_s }
    return unless @zones

    today = viewer_today
    count = HEART_RATE_WINDOWS.fetch(@granularity)
    from = if @granularity == "week"
      Allure::Stats::Trends.week_start_on_or_before(today, current_user.week_start) - ((count - 1) * 7)
    else
      today.beginning_of_month << (count - 1)
    end
    history = HeartRates::History.new(user: current_user)
    @periods = history.zone_totals(granularity: @granularity, from:, through: today, sport_id: @sport&.id)
    @selector_sports = heart_rate_selector_sports(history.recording_counts(from:, through: today))
  end

  private

  # The sport pills of the zone page (DESIGN.md §8.4, §10.6): the sports with
  # heart rate in the window, most recordings first, plus the active filter
  # even when it has none there.
  def heart_rate_selector_sports(counts)
    @sports.each_with_index
      .select { |sport, _index| counts[sport.id].positive? || sport == @sport }
      .sort_by { |sport, index| [ -counts[sport.id], index ] }
      .map { |sport, _index| { sport:, count: counts[sport.id], active: sport == @sport } }
  end

  def find_sport_if_requested
    return nil if params[:sport_id].blank?

    Sport.find(params[:sport_id])
  end

  # Groups aggregate hashes by sport (preloading display data) and drops
  # masked metrics per sport, so views render without conditionals. Stored
  # rows are never deleted for display; they are only hidden here.
  def group_for_tables(rows)
    sports = Sport.where(id: rows.map { |row| row[:sport_id] }.uniq).index_by(&:id)
    rows.group_by { |row| row[:sport_id] }.filter_map do |sport_id, sport_rows|
      sport = sports[sport_id]
      next unless sport

      visible = sport_rows.map { |row| row.slice(:period, *visible_metric_keys(sport)) }
      [ sport, visible ] unless visible.empty?
    end.sort_by { |sport, _| sport.position }.to_h
  end

  def visible_metric_keys(sport)
    keys = %i[total_workouts total_distance average_distance total_duration average_duration total_calories]
    if sport.records_elevation
      keys += %i[total_ascent average_ascent total_descent average_descent]
    end
    keys << :average_speed unless sport.pace_speed_display == "pace"
    keys << :average_pace unless sport.pace_speed_display == "speed"
    keys
  end
end
