# frozen_string_literal: true

module Allure
  module Virtual
    # Detects the jumps a virtual platform draws when it moves the athlete
    # without moving them (PLAN_VIRTUAL.md §7.1): a video route that ends by
    # returning the rider to its start, a world change, a respawn. The
    # recorded positions then jump kilometres in one second while the
    # ergometer's own cumulative distance keeps advancing normally, and a
    # single recording segment would draw a straight line across the map and
    # inflate every speed derived from it.
    #
    # A step is a teleport when it covers at least `MIN_STEP_M` and either
    # implies a speed no virtual sport reaches (`MAX_SPEED_MPS`) or is an order
    # of magnitude longer than what the device itself recorded for that step.
    # The recorded distance is the better witness when the file carries one;
    # a platform that writes none (EXR) falls back to its own speed reading,
    # then to the speed ceiling alone. A point with no position is never a
    # teleport: a positionless recording has no line to draw.
    module Teleports
      # Below this, a jump is GPS noise or a finish-line snap the outlier
      # filter handles; splitting would only create a meaningless segment.
      MIN_STEP_M = 200.0
      # 216 km/h: above every speed a virtual world renders, far below the
      # kilometres per second an actual teleport implies.
      MAX_SPEED_MPS = 60.0
      # A step ten times longer than the distance the device recorded for it
      # is the same jump, even when the device's own distance happened to
      # advance too.
      DISTANCE_FACTOR = 10.0

      module_function

      # The times at which a new recording segment must start: the first point
      # after each teleport. The parser merges them with its timer stops.
      def marks(points)
        points.each_cons(2).filter_map do |previous, current|
          next unless previous.positioned? && current.positioned?
          next if previous.time.nil? || current.time.nil?

          step = Allure::Gpx::Geo.horizontal_distance(
            previous.latitude, previous.longitude, current.latitude, current.longitude
          )
          next if step < MIN_STEP_M
          next unless teleport?(previous, current, step)

          current.time
        end
      end

      def teleport?(previous, current, step)
        duration = current.time - previous.time
        return true if duration.positive? && (step / duration) > MAX_SPEED_MPS

        expected = expected_distance(previous, current, duration)
        expected && step > (DISTANCE_FACTOR * expected)
      end

      # What the device says the athlete moved during the step: its cumulative
      # distance when both readings carry one, else its own speed. Nil when
      # the file recorded neither, leaving the speed ceiling as the only
      # witness.
      def expected_distance(previous, current, duration)
        recorded = distance_delta(previous, current)
        return recorded unless recorded.nil?

        speeds = [ previous.speed, current.speed ].compact
        return nil if speeds.empty? || !duration.positive?

        speeds.max * duration
      end

      def distance_delta(previous, current)
        return nil if previous.distance.nil? || current.distance.nil?

        delta = current.distance - previous.distance
        delta.negative? ? nil : delta
      end
    end
  end
end
