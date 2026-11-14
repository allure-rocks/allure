# frozen_string_literal: true

module Segments
  # The time between each given segment effort and the athlete's personal best
  # on the same (segment, sport), in seconds: positive for a slower effort, and
  # for the record itself its margin over the second best time (zero or
  # negative). An effort alone on its (segment, sport) has no gap. Derived on
  # read with the order of `Segments::PersonalPlaces`, owner-only, never
  # published.
  class PersonalBestGaps
    def initialize(user:, efforts:)
      @user = user
      @efforts = Array(efforts)
    end

    # { segment_effort_id => seconds } for the efforts that have a reference.
    WINDOW = <<~SQL.squish
      PARTITION BY segment_id, sport_id ORDER BY elapsed_time ASC, started_at ASC, id ASC
      ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    SQL

    def call
      return {} if @user.nil? || @efforts.empty?

      ranked = @user.segment_efforts
        .where(segment_id: @efforts.map(&:segment_id).uniq, sport_id: @efforts.map(&:sport_id).uniq)
        .select(:id, :elapsed_time, Arel.sql(<<~SQL.squish))
          ROW_NUMBER() OVER (#{WINDOW}) AS place,
          FIRST_VALUE(elapsed_time) OVER (#{WINDOW}) AS best_time,
          NTH_VALUE(elapsed_time, 2) OVER (#{WINDOW}) AS second_time
        SQL

      SegmentEffort.from(ranked, :segment_efforts)
        .where(id: @efforts.map(&:id))
        .pluck(:id, :elapsed_time, :place, :best_time, :second_time)
        .each_with_object({}) do |(id, elapsed, place, best, second), gaps|
          reference = place == 1 ? second : best
          gaps[id] = elapsed.to_i - reference.to_i unless reference.nil?
        end
    end
  end
end
