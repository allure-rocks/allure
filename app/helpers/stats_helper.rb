# frozen_string_literal: true

module StatsHelper
  # Formats an aggregate value by metric key in the viewer's unit system.
  # Nil-safe: a missing average (all-NULL inputs) renders as an em dash.
  def format_stat_value(key, value, sport: nil)
    case key.to_sym
    when :total_workouts, :total_calories then value&.to_i
    when :total_distance, :average_distance then format_distance(value)
    when :total_duration, :average_duration then format_duration(value)
    when :total_ascent, :average_ascent, :total_descent, :average_descent then format_elevation(value)
    when :average_speed then format_speed(value)
    when :average_pace then format_pace(value, sport:)
    end
  end

  def format_stat_period(period, granularity)
    case granularity.to_s
    when "month" then I18n.l(period, format: :month_year)
    when "year" then period.year.to_s
    else I18n.l(period)
    end
  end
end
