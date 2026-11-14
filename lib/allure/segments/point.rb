# frozen_string_literal: true

module Allure
  module Segments
    Point = Data.define(
      :index,
      :segment_index,
      :segment_point_index,
      :time,
      :elapsed_time,
      :distance,
      :longitude,
      :latitude,
      :elevation,
      :speed,
      :heart_rate,
      :cadence,
      :power
    ) do
      def initialize(
        index:,
        segment_index:,
        segment_point_index:,
        time:,
        elapsed_time:,
        distance:,
        longitude:,
        latitude:,
        elevation:,
        speed:,
        heart_rate:,
        cadence:,
        power:
      )
        super
      end

      def coordinate = [ longitude, latitude ].freeze
    end
  end
end
