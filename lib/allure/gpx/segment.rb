# frozen_string_literal: true

module Allure
  module Gpx
    # An immutable, ordered `<trkseg>`. The parser only ever builds a Segment
    # with two or more points; shorter segments are discarded during parsing.
    #
    # A segment is positioned when its first point is: a file's points are
    # either all positioned or all unpositioned, never mixed
    # (PLAN_NO_GPS.md).
    Segment = Data.define(:points) do
      def initialize(points:)
        super(points: points.frozen? ? points : points.freeze)
      end

      def size = points.size
      def first_point = points.first
      def last_point = points.last
      def positioned? = points.first&.positioned? || false
    end
  end
end
