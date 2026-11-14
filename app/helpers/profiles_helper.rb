# frozen_string_literal: true

module ProfilesHelper
  MIX_SPORTS = 5
  STATISTICS_METRICS = %i[total_workouts total_distance total_duration total_ascent].freeze

  def own_profile? = @profile_account == current_user

  def profile_stat_value(metric, value)
    return "—" if value.nil?

    case metric
    when :total_workouts then format_decimal(value.to_i)
    when :total_distance then format_distance(value)
    when :total_duration then format_duration_human(value)
    when :total_ascent then format_elevation(value)
    end
  end

  def profile_statistics_metrics(rows)
    STATISTICS_METRICS.select { |metric| rows.any? { |row| !row.public_send(metric).nil? } }
  end

  # Only already-shared totals, in stable sport order. Keep absent measurements
  # absent; the chart's logarithm never changes the underlying SI values.
  def profile_statistics_payload(rows, metric)
    raise ArgumentError, "unknown profile statistic" unless STATISTICS_METRICS.include?(metric)

    entries = rows.filter_map do |row|
      value = row.public_send(metric)
      next if value.nil?

      { name: sport_display_name(row.sport), value: value.to_f, formatted: profile_stat_value(metric, value) }
    end
    { entries:, maximum: profile_stat_value(metric, entries.map { |entry| entry[:value] }.max) }
  end

  def profile_name
    @profile_account.is_a?(User) ? @profile_account.display_name : actor_name(@profile_account)
  end

  def profile_handle
    if @profile_account.is_a?(User)
      "@#{Allure::Federation::Config.enabled? ? @profile_account.handle : @profile_account.username}"
    else
      actor_handle(@profile_account)
    end
  end

  def profile_bio
    if @profile_account.is_a?(User)
      simple_format(h(@profile_account.bio)) if @profile_account.bio.present?
    elsif @profile_account.summary.present?
      Federation::RemoteText.sanitize(@profile_account.summary)
    end
  end

  # Only known journal choices become URL options; arbitrary query parameters
  # can never turn a filter link into another host or another route.
  def profile_journal_path(period: @journal.period, sport: @journal.selected_sport&.key)
    options = { period: (period unless period == "all"), sport: }.compact
    if @profile_account.is_a?(User)
      profile_path(@profile_account.username, **options)
    else
      remote_profile_path(@profile_account.acct.presence || @profile_account.handle, **options)
    end
  end

  def profile_sport_mix_payload
    entries = @journal.selector_sports
    slices = entries.first(MIX_SPORTS).map do |entry|
      name = sport_display_name(entry.sport)
      {
        name:, values: { workouts: entry.count },
        url: profile_journal_path(sport: entry.key), open_label: t("me.mix.open", sport: name)
      }
    end
    remaining = entries.drop(MIX_SPORTS).sum(&:count)
    slices << { name: t("me.mix.others"), values: { workouts: remaining }, url: nil, open_label: nil } if remaining.positive?

    {
      labels: { workouts: t("profile.journal.title") },
      slices:,
      total_label: t("profile.journal.title"),
      unit_system: current_user.unit_system,
      locale: I18n.locale.to_s
    }
  end
end
