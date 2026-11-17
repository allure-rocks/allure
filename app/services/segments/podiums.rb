# frozen_string_literal: true

module Segments
  # The index rows' board summary (docs/dev/SEGMENTS.md): for each row
  # — one course and one sport — the top three of that sport's board as the
  # viewer reads it, plus the viewer's own best in that sport and their
  # standing. A row without a sport (an all-sports course nobody ran) has no
  # board; a private course has none either, so `top` stays empty and
  # `viewer_effort` carries the owner's personal best.
  #
  # Eligibility, aliasing and anonymity stay in the read layer: this service
  # only reads the same ranking as the leaderboard page, and the view resolves
  # names through the shared alias rules.
  class Podiums
    Row = Data.define(:segment, :sport, :top, :participants, :viewer_effort, :viewer_rank, :viewer_ranked)

    TOP_SIZE = 3

    # `rows` are the list query's segments, each carrying `row_sport_id`.
    def initialize(rows:, viewer:)
      @rows = rows
      @viewer = viewer
    end

    # A hash keyed by [segment id, row sport id], so a page reads its row in O(1).
    def call
      return {} if @rows.empty? || @viewer.nil?

      segment_ids = @rows.map(&:id).uniq
      rankings = Rankings.by_segment_and_sport(segment_ids, viewer: @viewer)
      viewer_efforts = Rankings.viewer_best_by_segment(segment_ids, @viewer)
      sports = Sport.where(id: @rows.filter_map { self.class.sport_id(it) }.uniq).index_by(&:id)

      @rows.to_h do |segment|
        sport_id = self.class.sport_id(segment)
        [ [ segment.id, sport_id ], build_row(segment, sports[sport_id], rankings, viewer_efforts.fetch(segment.id, {})) ]
      end
    end

    def self.sport_id(segment) = segment.attributes.fetch("row_sport_id", segment.sport_id)

    private

    def build_row(segment, sport, rankings, viewer_by_sport)
      ranking = sport ? rankings.fetch([ segment.id, sport.id ], []) : []
      viewer_effort = sport && viewer_by_sport[sport.id]
      rank = ranking.index { |effort| effort.user_id == @viewer.id }

      Row.new(
        segment:,
        sport:,
        top: ranking.first(TOP_SIZE),
        participants: ranking.size,
        viewer_effort:,
        viewer_rank: rank && rank + 1,
        viewer_ranked: !rank.nil?
      )
    end
  end
end
