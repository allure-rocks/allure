# frozen_string_literal: true

module Allure
  module Geometry
    # Places direction chevrons along an already-projected polyline. The route
    # image renderers work in canvas pixels, so the spacing is a screen
    # constant and the angle is the local tangent in degrees clockwise from
    # east, which is exactly the SVG rotate convention (canvas y grows down).
    #
    # A chevron dropped at a fixed distance can land exactly on a corner, where
    # its tangent changes abruptly and the arrow reads as pointing the wrong
    # way. Each ideal position therefore owns a slot around it, and the chevron
    # is placed on the straightest candidate inside that slot. The slot is
    # narrow enough that the spacing still looks regular.
    module DirectionChevrons
      SPACING = 320.0
      CLEARANCE = 24.0

      # The slot and the direction window are both a third of the spacing, so
      # a chevron can move far enough to clear a corner without drifting into
      # its neighbour's slot. They scale with a caller-supplied spacing.
      SLOT_SAMPLES = 9

      # A real GPS trace never has an exactly straight window, so candidates
      # within this many degrees of the straightest one are considered equal
      # and the closest to the slot centre wins. Without it, the smallest
      # jitter would make the anchors wander inside their slots.
      STRAIGHTNESS_TOLERANCE_DEGREES = 2.0

      Placement = Data.define(:x, :y, :angle, :distance, :side)

      def self.placements(points, spacing: SPACING, clearance: CLEARANCE, covered: {}, closure: spacing / 24.0)
        coordinates = Array(points)
        return [] if coordinates.length < 2

        lengths = cumulative_lengths(coordinates)
        total = lengths.last
        return [] if total <= 0

        placements = []
        slot_half = spacing / 3.0
        lookahead = spacing / 3.0
        distance = spacing / 2.0
        while distance < total
          placement = straightest_placement(coordinates, lengths, total, distance, slot_half, lookahead, clearance)
          placements << placement if placement
          distance += spacing
        end

        # A trace shorter than the first ideal position still deserves one
        # chevron: take the straightest point of the whole drawable range.
        if placements.empty? && total > (2 * clearance)
          placement = straightest_placement(coordinates, lengths, total, total / 2.0, total / 2.0, lookahead, clearance)
          placements << placement if placement
        end

        sides = LoopExterior.sides(coordinates, distances: placements.map(&:distance), closure:)
        placements = placements.each_with_index.map { |placement, index| placement.with(side: sides[index]) }
        without_repeated_laps(placements, coordinates, lengths, total, spacing, lookahead, covered)
      end

      # Cover the whole slot, so a later lap with shifted anchors still shares
      # the first lap's arrows. Opposite directions remain distinct.
      def self.without_repeated_laps(placements, coordinates, lengths, total, spacing, lookahead, covered)
        tolerance = spacing / 24.0
        placements.reject do |placement|
          cell_x = (placement.x / tolerance).floor
          cell_y = (placement.y / tolerance).floor
          duplicate = (-1..1).any? do |dx|
            (-1..1).any? do |dy|
              covered.fetch([ cell_x + dx, cell_y + dy ], []).any? do |x, y, angle|
                Math.hypot(x - placement.x, y - placement.y) <= tolerance &&
                  (((angle - placement.angle + 540) % 360) - 180).abs < 30
              end
            end
          end
          unless duplicate
            (0..48).each do |index|
              at = (placement.distance - spacing / 2.0 + index * spacing / 48.0).clamp(0, total)
              x, y = point_at(coordinates, lengths, at)
              key = [ (x / tolerance).floor, (y / tolerance).floor ]
              (covered[key] ||= []) <<
                [ x, y, placement_angle(coordinates, lengths, at, total, lookahead) ]
            end
          end
          duplicate
        end
      end
      private_class_method :without_repeated_laps

      def self.cumulative_lengths(coordinates)
        lengths = [ 0.0 ]
        coordinates.each_cons(2) do |from, to|
          lengths << lengths.last + Math.hypot(to[0] - from[0], to[1] - from[1])
        end
        lengths
      end
      private_class_method :cumulative_lengths

      # One chevron in the slot centred on `center`, at the candidate whose
      # incoming and outgoing directions disagree the least. Candidates within
      # the straightness tolerance of the best one are equally acceptable, and
      # the closest to the slot centre wins among them, so regular spacing
      # survives GPS jitter while true corners are still avoided.
      def self.straightest_placement(coordinates, lengths, total, center, slot_half, lookahead, clearance)
        low = [ center - slot_half, clearance ].max
        high = [ center + slot_half, total - clearance ].min
        return nil if high < low

        candidates = (0...SLOT_SAMPLES).map do |index|
          ratio = SLOT_SAMPLES == 1 ? 0.5 : index / (SLOT_SAMPLES - 1.0)
          at = low + ((high - low) * ratio)
          { at:, turn: turn_degrees(coordinates, lengths, at, total, lookahead) }
        end
        best_turn = candidates.map { |candidate| candidate[:turn] }.min
        at = candidates
             .select { |candidate| candidate[:turn] <= best_turn + STRAIGHTNESS_TOLERANCE_DEGREES }
             .min_by { |candidate| (candidate[:at] - center).abs }
             .fetch(:at)

        x, y = point_at(coordinates, lengths, at)
        Placement.new(x:, y:, angle: placement_angle(coordinates, lengths, at, total, lookahead), distance: at, side: 1)
      end
      private_class_method :straightest_placement

      # Angle in degrees between the direction before the candidate and the
      # direction after it, in [0, 180]. Zero is a perfectly straight run.
      def self.turn_degrees(coordinates, lengths, at, total, lookahead)
        before = direction_between(coordinates, lengths, [ at - lookahead, 0.0 ].max, at)
        after = direction_between(coordinates, lengths, at, [ at + lookahead, total ].min)
        return 0.0 if before.nil? || after.nil?

        cross = (before[0] * after[1]) - (before[1] * after[0])
        dot = (before[0] * after[0]) + (before[1] * after[1])
        Math.atan2(cross.abs, dot) * 180.0 / Math::PI
      end
      private_class_method :turn_degrees

      # Direction over a window centred on the chosen point, so the glyph
      # follows the local run instead of one noisy edge.
      def self.placement_angle(coordinates, lengths, at, total, lookahead)
        from = [ at - lookahead, 0.0 ].max
        to = [ at + lookahead, total ].min
        delta_x, delta_y = direction_between(coordinates, lengths, from, to)
        return 0.0 if delta_x.nil? || delta_y.nil?

        Math.atan2(delta_y, delta_x) * 180.0 / Math::PI
      end
      private_class_method :placement_angle

      def self.direction_between(coordinates, lengths, from_distance, to_distance)
        from = point_at(coordinates, lengths, from_distance)
        to = point_at(coordinates, lengths, to_distance)
        return nil if from.nil? || to.nil?

        [ to[0] - from[0], to[1] - from[1] ]
      end
      private_class_method :direction_between

      def self.point_at(coordinates, lengths, distance)
        return coordinates.first.dup if distance <= 0
        return coordinates.last.dup if distance >= lengths.last

        index = lengths.bsearch_index { |length| length >= distance } || lengths.length - 1
        index = 1 if index.zero?
        previous = lengths[index - 1]
        span = lengths[index] - previous
        from = coordinates[index - 1]
        to = coordinates[index]
        return [ from[0], from[1] ] unless span.positive?

        ratio = (distance - previous) / span
        [ from[0] + ((to[0] - from[0]) * ratio), from[1] + ((to[1] - from[1]) * ratio) ]
      end
      private_class_method :point_at
    end
  end
end
