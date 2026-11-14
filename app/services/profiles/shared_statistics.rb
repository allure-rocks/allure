# frozen_string_literal: true

module Profiles
  # Deliberately shared all-history volumes, not publication aggregates. The
  # audience is checked before any workout query; only the four permitted totals
  # leave the database. No dates, workout identities, averages or health data.
  class SharedStatistics
    Row = Data.define(:sport, :total_workouts, :total_distance, :total_duration, :total_ascent)

    def initialize(user:, viewer:)
      @user = user
      @policy = SharingPolicy.new(user:, viewer:)
    end

    def call
      return [] unless @policy.allowed?(audience: @user.profile_statistics_audience)

      totals = @user.workouts.group(:sport_id).pluck(
        :sport_id, Arel.sql("COUNT(*)"), Arel.sql("SUM(distance)"),
        Arel.sql("SUM(moving_time)"), Arel.sql("SUM(ascent)")
      )
      sports = Sport.where(id: totals.map(&:first)).index_by(&:id)
      totals.map do |sport_id, count, distance, duration, ascent|
        sport = sports.fetch(sport_id)
        Row.new(sport:, total_workouts: count, total_distance: (distance if distance&.positive?),
                total_duration: duration, total_ascent: (ascent if sport.records_elevation?))
      end.sort_by { |row| row.sport.position }
    end
  end
end
