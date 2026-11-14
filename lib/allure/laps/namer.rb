# frozen_string_literal: true

module Allure
  module Laps
    # Picks a human label for a detected lap from the workout's already-fetched
    # toponymy: curated markers first, then strict climb summits, then the start
    # place. No geocoding happens here; when the toponymy is absent, pending, or
    # carries no usable name the lap stays nameless and the view falls back to
    # its generic label.
    class Namer
      CLIMB_RADIUS_METRES = 750.0
      PLACE_RADIUS_METRES = 1_000.0
      KIND_PRIORITY = %w[
        summit pass landmark viewpoint waterfall spring cave hut route city town
        village hamlet locality isolated_dwelling municipality suburb neighbourhood
      ].freeze

      def initialize(lap:, toponymy:)
        @lap = lap
        @toponymy = toponymy
      end

      def call
        return unless geocoded?

        case @lap.source
        when "climb" then nearest_name(@lap.end_distance, CLIMB_RADIUS_METRES)
        when "descent" then descent_name
        when "loop" then loop_name
        when "pause", "stop" then nearest_name(@lap.start_distance, PLACE_RADIUS_METRES)
        end
      end

      private

      def geocoded?
        @toponymy.respond_to?(:ready?) && (@toponymy.ready? || @toponymy.partial?)
      end

      # A descent is named after the pass it starts from when one is known,
      # otherwise after the place it reaches.
      def descent_name
        named_kind_near(@lap.start_distance, %w[pass summit], CLIMB_RADIUS_METRES) ||
          nearest_name(@lap.end_distance, CLIMB_RADIUS_METRES)
      end

      def named_kind_near(distance, kinds, radius)
        candidates = (markers + summits).select do |candidate|
          kinds.include?(candidate[:kind]) && (candidate[:distance] - distance).abs <= radius
        end
        candidates.min_by { |candidate| (candidate[:distance] - distance).abs }&.fetch(:name)
      end

      def loop_name
        inside = markers.select { |marker| marker[:distance].between?(@lap.start_distance, @lap.end_distance) }
        closest = inside.min_by { |marker| [ priority_index(marker[:kind]), marker[:distance] - @lap.start_distance ] }
        return closest[:name] if closest

        nearest_name(@lap.start_distance, PLACE_RADIUS_METRES) || start_place_name
      end

      def nearest_name(distance, radius)
        candidates = markers + summits
        within = candidates.select { |candidate| (candidate[:distance] - distance).abs <= radius }
        within.min_by { |candidate| [ priority_index(candidate[:kind]), (candidate[:distance] - distance).abs ] }
          &.fetch(:name)
      end

      def start_place_name
        place = @toponymy.start_place
        return unless place.is_a?(Hash)

        name = place["name"] || place[:name]
        name.to_s.strip.presence&.truncate(120)
      end

      def markers
        @markers ||= Array(@toponymy.markers).filter_map do |marker|
          entry = marker.respond_to?(:to_h) ? marker.to_h : {}
          distance = entry["distance"] || entry[:distance]
          name = (entry["name"] || entry[:name]).to_s.strip
          next unless distance.is_a?(Numeric) && distance.finite? && name.present?

          { distance: distance.to_f, name: name.truncate(120), kind: (entry["kind"] || entry[:kind]).to_s }
        end
      end

      def summits
        @summits ||= Array(@toponymy.samples).filter_map do |sample|
          entry = sample.respond_to?(:to_h) ? sample.to_h : {}
          next unless (entry["role"] || entry[:role]) == "climb_summit"

          result = entry["result"] || entry[:result]
          feature = result.is_a?(Hash) ? (result["feature"] || result[:feature]) : nil
          name = feature.is_a?(Hash) ? (feature["name"] || feature[:name]).to_s.strip : ""
          distance = entry["distance"] || entry[:distance]
          next unless distance.is_a?(Numeric) && distance.finite? && name.present?

          { distance: distance.to_f, name: name.truncate(120), kind: "summit" }
        end
      end

      def priority_index(kind)
        KIND_PRIORITY.index(kind.to_s) || KIND_PRIORITY.length
      end
    end
  end
end
