# frozen_string_literal: true

module Allure
  module Geometry
    # Spatial visits, not all pairs of track points. Anchors are at least 10 m
    # apart; each cell, anchor history and final shortlist has a fixed budget.
    # Discovery is approximate: only the ordinary segment matcher may accept a
    # repeated circuit. Coordinates and indexes always refer to the source.
    class LoopCandidates
      ANCHOR_SPACING = 10.0
      MAX_CELL_ANCHORS = 16
      MAX_LENGTH_GROUPS = 4
      MAX_CANDIDATES = 32
      EARTH_RADIUS = 6_378_137.0
      CELL_OFFSETS = [ -1, 0, 1 ].repeated_permutation(3).map(&:freeze).freeze
      Anchor = Struct.new(:coordinate, :visit, :previous_visit, :groups)
      Visit = Data.define(:index, :distance, :gap)
      Group = Struct.new(:start_index, :end_index, :distance, :count)
      Result = Data.define(:candidate, :occurrences)

      def initialize(coordinates, min_loop_distance: 400.0, closure_radius: 30.0)
        @points = LoopDetector.normalize_coordinates(coordinates)
        @minimum = LoopDetector.positive_float(min_loop_distance, "min_loop_distance")
        @radius = LoopDetector.positive_float(closure_radius, "closure_radius")
        @cells = Hash.new { |hash, key| hash[key] = [] }
        @active = []
        @lengths = [ 0.0 ]
      end

      def call
        ranked.map(&:candidate)
      end

      def ranked
        @points.each_with_index { |point, index| visit(point, index) }
        @active.each { |anchor| finish_visit(anchor) }
        shortlist.filter_map do |group|
          coordinates = @points[group.start_index..group.end_index]
          sampled = Resampler.resample(coordinates, count: LoopDetector::RETRACE_SAMPLE_COUNT)
          next if Frechet.distance(sampled, sampled.reverse, band: nil) <= @radius

          candidate = LoopDetector::Candidate.new(
            start_index: group.start_index, end_index: group.end_index,
            travelled_distance_meters: group.distance,
            closure_distance_meters: distance(coordinates.first, coordinates.last),
            coordinates: coordinates.freeze
          )
          Result.new(candidate:, occurrences: group.count)
        end
      end

      private

      def visit(point, index)
        @lengths << @lengths.last + distance(@points[index - 1], point) if index.positive?
        cell = cell_for(point)
        nearby = neighbors(cell).flat_map { |key| @cells.fetch(key, []) }.filter_map do |anchor|
          gap = distance(anchor.coordinate, point)
          [ anchor, gap ] if gap <= @radius
        end
        present = nearby.map(&:first)
        (@active - present).each { |anchor| finish_visit(anchor) }
        nearby.each do |anchor, gap|
          if anchor.visit.nil? || gap < anchor.visit.gap
            anchor.visit = Visit.new(index:, distance: @lengths.last, gap:)
          end
        end
        if nearby.none? { |_anchor, gap| gap < ANCHOR_SPACING } && @cells[cell].length < MAX_CELL_ANCHORS
          anchor = Anchor.new(point, Visit.new(index:, distance: @lengths.last, gap: 0.0), nil, [])
          @cells[cell] << anchor
          present << anchor
        end
        @active = present
      end

      def finish_visit(anchor)
        current = anchor.visit
        previous = anchor.previous_visit
        if previous && current.distance - previous.distance >= @minimum
          length = current.distance - previous.distance
          group = anchor.groups.find { |item| (length - item.distance).abs <= item.distance * 0.1 }
          if group
            group.count += 1
          elsif anchor.groups.length < MAX_LENGTH_GROUPS
            anchor.groups << Group.new(previous.index, current.index, length, 1)
          end
        end
        anchor.previous_visit = current
        anchor.visit = nil
      end

      def shortlist
        best = []
        @cells.each_value do |anchors|
          anchors.each do |anchor|
            anchor.groups.each do |group|
              best << group
              best.sort_by! { |item| [ -(item.count >= 2 ? 1 : 0), -(item.distance * item.count), item.distance, item.start_index ] }
              best.pop if best.length > MAX_CANDIDATES
            end
          end
        end
        best
      end

      # Earth-centred cells avoid a longitude seam and remain bounded at poles.
      def cell_for(point)
        longitude, latitude = point.map { |value| value * Math::PI / 180.0 }
        radius = EARTH_RADIUS / @radius
        [ radius * Math.cos(latitude) * Math.cos(longitude),
          radius * Math.cos(latitude) * Math.sin(longitude),
          radius * Math.sin(latitude) ].map(&:floor)
      end

      def neighbors(cell)
        x, y, z = cell
        CELL_OFFSETS.map { |dx, dy, dz| [ x + dx, y + dy, z + dz ] }
      end

      def distance(first, second)
        LoopDetector.horizontal_distance(first, second)
      end
    end
  end
end
