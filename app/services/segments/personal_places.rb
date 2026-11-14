# frozen_string_literal: true

module Segments
  # The athlete's personal place of each given segment effort among all their
  # own efforts on the same (segment, sport): 1 is the record (the
  # `personal_best` effort), 2 and 3 the second and third best time
  # (DESIGN.md §10.4). Derived on read, never stored, never published, and
  # distinct from the leaderboard rank, which places athletes. The order
  # mirrors `Segments::MatchWorkoutJob#recompute_personal_best`.
  class PersonalPlaces
    LIMIT = 3

    def initialize(user:, efforts:)
      @user = user
      @efforts = Array(efforts)
    end

    # { segment_effort_id => place } for the efforts placed in the top three.
    def call
      return {} if @user.nil? || @efforts.empty?

      ranked = @user.segment_efforts
        .where(segment_id: @efforts.map(&:segment_id).uniq, sport_id: @efforts.map(&:sport_id).uniq)
        .select(:id, Arel.sql(<<~SQL.squish))
          ROW_NUMBER() OVER (PARTITION BY segment_id, sport_id
                             ORDER BY elapsed_time ASC, started_at ASC, id ASC) AS place
        SQL

      SegmentEffort.from(ranked, :segment_efforts)
        .where(id: @efforts.map(&:id))
        .where("place <= ?", LIMIT)
        .pluck(:id, :place)
        .to_h
    end
  end
end
