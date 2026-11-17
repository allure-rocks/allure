# frozen_string_literal: true

module Segments
  # The viewer's position on each board they read and have run: one row per
  # (segment, sport) they have an effort on, carrying the rank and time the
  # board shows them plus the number of athletes they see ranked. A viewer whose effort is not
  # eligible still gets a row, flagged `ranked: false` (docs/dev/SEGMENTS.md).
  #
  # Two queries cover a whole page of segments: the eligible efforts that make
  # up each ranking, and the viewer's own efforts (ranked or not).
  class Standings
    Row = Data.define(:segment, :sport, :rank, :participants, :elapsed_time, :average_pace, :average_speed, :ranked)

    def initialize(segments:, viewer:)
      @segments = segments
      @viewer = viewer
    end

    def call
      return [] if @viewer.nil? || @segments.empty?

      segment_ids = @segments.map(&:id)
      rankings = ranked_rankings(segment_ids)
      viewer_efforts = viewer_efforts_by_segment(segment_ids)

      @segments.flat_map do |segment|
        sports = viewer_efforts.fetch(segment.id, {})
        sports.sort_by { |_sport_id, effort| effort.sport.position }.map do |sport_id, effort|
          ranking = rankings.fetch([ segment.id, sport_id ], [])
          index = ranking.index { |effort| effort.user_id == @viewer.id }
          selected = index ? ranking[index] : effort
          Row.new(
            segment:,
            sport: effort.sport,
            rank: index && index + 1,
            participants: ranking.size,
            elapsed_time: selected.elapsed_time,
            average_pace: selected.average_pace,
            average_speed: selected.average_speed,
            ranked: !index.nil?
          )
        end
      end
    end

    private

    def ranked_rankings(segment_ids)
      Rankings.by_segment_and_sport(segment_ids, viewer: @viewer)
    end

    def viewer_efforts_by_segment(segment_ids)
      Rankings.viewer_best_by_segment(segment_ids, @viewer)
    end
  end
end
