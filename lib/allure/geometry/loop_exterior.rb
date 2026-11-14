# frozen_string_literal: true

module Allure
  module Geometry
    # Display-only topology in a projected plane whose y grows down. Closed
    # excursions are erased from the working path, so each lobe of a figure
    # eight has its own winding. Mirrors frontend/lib/loop_exterior.js.
    module LoopExterior
      CLOSURE_METRES = 30.0
      MAX_SAMPLES = 20_000
      MAX_CELL_VISITS = 32
      Node = Data.define(:x, :y, :at, :key, :index, :area)
      Range = Data.define(:start, :finish, :side)

      def self.sides(points, distances:, closure: 10.0)
        sides = Array.new(distances.length, 1)
        return sides if points.length < 3 || closure <= 0 || distances.empty?
        origin_x, origin_y = points.first
        points = points.map { |x, y| [ x - origin_x, y - origin_y ] }

        lengths = [ 0.0 ]
        points.each_cons(2) { |from, to| lengths << lengths.last + Math.hypot(to[0] - from[0], to[1] - from[1]) }
        total = lengths.last
        return sides if total < 8 * closure

        stack = []
        grid = {}
        ranges = []
        count = [ MAX_SAMPLES, (total / (closure / 2.0)).ceil ].min
        edge = 1

        (0..count).each do |index|
          at = total * index / count
          edge += 1 while edge < points.length - 1 && lengths[edge] < at
          span = lengths[edge] - lengths[edge - 1]
          ratio = span.positive? ? (at - lengths[edge - 1]) / span : 0.0
          x = points[edge - 1][0] + ratio * (points[edge][0] - points[edge - 1][0])
          y = points[edge - 1][1] + ratio * (points[edge][1] - points[edge - 1][1])
          previous = stack.last
          area = previous ? previous.area + cross(previous.x, previous.y, x, y) : 0.0
          cell_x = (x / closure).floor
          cell_y = (y / closure).floor
          match = nil
          winding = nil
          nearest = Float::INFINITY

          (-1..1).each do |dx|
            (-1..1).each do |dy|
              grid.fetch([ cell_x + dx, cell_y + dy ], []).each do |candidate|
                perimeter = at - candidate.at
                next if perimeter < 8 * closure

                gap = Math.hypot(x - candidate.x, y - candidate.y)
                next if gap > closure || gap >= nearest

                candidate_winding = area - candidate.area + cross(x, y, candidate.x, candidate.y)
                next if candidate_winding.abs <= 2 * closure * perimeter

                match = candidate
                winding = candidate_winding
                nearest = gap
              end
            end
          end

          if match
            ranges << Range.new(start: match.at - closure, finish: at + closure, side: winding.positive? ? -1 : 1)
            while stack.length > match.index
              removed = stack.pop
              bucket = grid[removed.key]
              bucket&.delete(removed)
              grid.delete(removed.key) if bucket&.empty?
            end
          end

          tail = stack.last
          key = [ cell_x, cell_y ]
          node = Node.new(x:, y:, at:, key:, index: stack.length, area: tail ? tail.area + cross(tail.x, tail.y, x, y) : 0.0)
          stack << node
          bucket = (grid[key] ||= [])
          bucket.delete_at(MAX_CELL_VISITS / 2) if bucket.length == MAX_CELL_VISITS
          bucket << node
        end

        assign_sides(sides, distances, ranges)
      end

      def self.assign_sides(sides, distances, ranges)
        # Assign each arrow once: an inner loop keeps its side if a later,
        # larger excursion surrounds it. No loops × arrows nested scan.
        successors = (0..distances.length).to_a
        ranges.each do |range|
          first = distances.bsearch_index { |distance| distance >= range.start } || distances.length
          index = unassigned(successors, first)
          while index < distances.length && distances[index] <= range.finish
            sides[index] = range.side
            successors[index] = unassigned(successors, index + 1)
            index = unassigned(successors, index)
          end
        end
        sides
      end
      private_class_method :assign_sides

      def self.unassigned(successors, index)
        root = index
        root = successors[root] while successors[root] != root
        while successors[index] != index
          following = successors[index]
          successors[index] = root
          index = following
        end
        root
      end
      private_class_method :unassigned

      def self.cross(x1, y1, x2, y2)
        x1 * y2 - y1 * x2
      end
      private_class_method :cross
    end
  end
end
