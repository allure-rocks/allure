# frozen_string_literal: true

module BestEfforts
  # The owner's personal place of each given best effort among all their own
  # efforts over the same (sport, distance): 1 is the record, 2 and 3 the
  # second and third best time (DESIGN.md §10.4). Derived on read, never
  # stored, never published. The order mirrors `Records::RecomputeService`
  # (duration, then the earlier start, then the earlier row), so place 1 is the
  # effort its `EffortRecord` points at.
  class PersonalPlaces
    LIMIT = 3

    def initialize(user:, best_efforts:)
      @user = user
      @best_efforts = Array(best_efforts)
    end

    # { best_effort_id => place } for the efforts placed in the top three.
    def call
      return {} if @user.nil? || @best_efforts.empty?

      ranked = @user.best_efforts
        .where(sport_id: @best_efforts.map(&:sport_id).uniq, distance_key: @best_efforts.map(&:distance_key).uniq)
        .select(:id, Arel.sql(<<~SQL.squish))
          ROW_NUMBER() OVER (PARTITION BY sport_id, distance_key
                             ORDER BY duration_seconds ASC, started_at ASC, id ASC) AS place
        SQL

      BestEffort.from(ranked, :best_efforts)
        .where(id: @best_efforts.map(&:id))
        .where("place <= ?", LIMIT)
        .pluck(:id, :place)
        .to_h
    end
  end
end
