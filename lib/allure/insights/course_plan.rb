# frozen_string_literal: true

module Allure
  module Insights
    # Where the route is cut for the assistant (docs/dev/AI.md §3.3). It reads
    # the climbs and descents the laps already detected — the same ones the
    # workout page shows — and turns them into contiguous sections: the climbs,
    # the descents and what lies between them. When the terrain is missing or
    # the route holds nothing worth naming, equal parts give the model the
    # shape of the outing instead.
    #
    # Pure and deterministic: no database, no clock, every tie broken.
    class CoursePlan
      MAX_SECTIONS = 8
      MIN_COURSE = 3_000.0
      MIN_SECTION = 500.0
      MIN_SECTION_SHARE = 0.05
      # A flat chunk longer than this is a feature of its own, not a gap to
      # swallow into the neighbouring climb.
      MAX_ABSORBED_SECTION = 1_500.0
      PARTS = { short: 3, long: 4 }.freeze
      PARTS_THRESHOLD = 8_000.0
      TERRAINS = %w[climb descent between part].freeze

      # `terrain` is "climb", "descent", "between" (resolved to flat or rolling
      # once the section is measured) or "part" for the equal cut. `number`,
      # `height` and `grade` come from the detected lap: they help the trimming
      # and name the climb, and are never measured twice.
      Slot = Data.define(:start_distance, :end_distance, :terrain, :name, :number, :height, :grade) do
        def length = end_distance - start_distance
        def between? = terrain == "between"
        def feature? = %w[climb descent].include?(terrain)
      end

      Plan = Data.define(:mode, :slots) do
        def boundaries = [ slots.first.start_distance, *slots.map(&:end_distance) ]
      end

      class << self
        def terrain(total:, detected:) = new(total.to_f).terrain(detected)

        def parts(total:) = new(total.to_f).parts
      end

      def initialize(total)
        @total = total.to_f
      end

      # The plan cut on the detected terrain, nil when the route is too short,
      # holds no feature, or the detected laps contradict each other too much
      # to leave a contiguous cut.
      def terrain(detected)
        return if total < MIN_COURSE

        features = features(detected)
        return if features.empty?

        slots = trim(slots_from(features))
        return if slots.empty? || slots.first.start_distance > 0 || slots.last.end_distance < total

        Plan.new(mode: :terrain, slots:)
      end

      # The equal cut, for a flat route or one whose elevation cannot be
      # trusted. A quiet route still has a beginning, a middle and an end.
      def parts
        return if total < MIN_COURSE

        count = total < PARTS_THRESHOLD ? PARTS[:short] : PARTS[:long]
        edges = (1...count).map { |index| total * index / count }
        slots = ([ 0.0 ] + edges + [ total ]).each_cons(2).map do |from, to|
          Slot.new(start_distance: from, end_distance: to, terrain: "part", name: nil, number: nil,
                   height: 0.0, grade: nil)
        end
        Plan.new(mode: :parts, slots:)
      end

      private

      attr_reader :total

      def features(detected)
        rows = %w[climb descent].flat_map do |terrain|
          values = detected.is_a?(Hash) ? (detected[terrain] || detected[terrain.to_sym]) : nil
          Array(values).filter_map { |row| feature(row, terrain) }
        end
        return [] if rows.empty?

        accepted = []
        # The tallest first, then the earliest: an overlap never keeps two
        # claims on the same ground.
        rows.sort_by { |item| [ -item.height, -item.length, item.start_distance, item.terrain, item.number.to_i ] }
            .each do |item|
          next if accepted.any? { overlap?(item, it) }

          accepted << item
        end
        accepted.sort_by { |item| [ item.start_distance, item.end_distance, item.terrain, item.number.to_i ] }
      end

      def feature(row, terrain)
        return unless row.is_a?(Hash)

        start = row[:start_distance].to_f.clamp(0.0, total)
        finish = row[:end_distance].to_f.clamp(0.0, total)
        return unless finish > start

        height = terrain == "climb" ? row[:ascent].to_f : row[:descent].to_f
        Slot.new(start_distance: start, end_distance: finish, terrain:, name: row[:name].presence,
                 number: row[:number], height:, grade: row[:average_grade])
      end

      def overlap?(first, second)
        first.start_distance < second.end_distance && second.start_distance < first.end_distance
      end

      def slots_from(features)
        slots = []
        cursor = 0.0
        features.each do |item|
          slots << between(cursor, item.start_distance) if item.start_distance > cursor
          slots << item
          cursor = item.end_distance
        end
        slots << between(cursor, total) if cursor < total
        slots
      end

      def between(from, to)
        Slot.new(start_distance: from, end_distance: to, terrain: "between", name: nil, number: nil,
                 height: 0.0, grade: nil)
      end

      # A gap shorter than the threshold is part of its neighbour: it never
      # deserves its own line in the table.
      def trim(slots)
        slots = absorb_small(slots)
        while slots.length > MAX_SECTIONS
          pair = shortest_between_pair(slots)
          if pair
            slots = merge_pair(slots, pair)
          else
            index = weakest_feature(slots)
            break unless index

            slots = merge_around(slots, index)
          end
        end
        absorb_small(slots)
      end

      def absorb_small(slots)
        slots = slots.dup
        threshold = [ [ total * MIN_SECTION_SHARE, MIN_SECTION ].max, MAX_ABSORBED_SECTION ].min
        index = 0
        while index < slots.length
          slot = slots[index]
          if slots.length > 1 && slot.between? && slot.length < threshold
            if index.positive?
              slots[index - 1] = extend_end(slots[index - 1], slot.end_distance)
            else
              slots[1] = extend_start(slots[1], slot.start_distance)
            end
            slots.delete_at(index)
            index = [ index - 1, 0 ].max
          else
            index += 1
          end
        end
        slots
      end

      def shortest_between_pair(slots)
        best = nil
        slots.each_cons(2).with_index do |(first, second), index|
          next unless first.between? && second.between?

          length = first.length + second.length
          best = [ index, length ] if best.nil? || length < best[1]
        end
        best&.first
      end

      def merge_pair(slots, index)
        merged = between(slots[index].start_distance, slots[index + 1].end_distance)
        slots = slots.dup
        slots[index] = merged
        slots.delete_at(index + 1)
        slots
      end

      # The smallest feature loses its name and its height first: the table
      # keeps the climb that tells the story.
      def weakest_feature(slots)
        candidates = slots.each_index.select { |index| slots[index].feature? }
        candidates.min_by { |index| [ slots[index].height, slots[index].length, slots[index].number.to_i ] }
      end

      # A demoted feature becomes ground of its own with its neighbours: the
      # table loses two lines, never one.
      def merge_around(slots, index)
        start = index.positive? ? index - 1 : index
        finish = index < slots.length - 1 ? index + 1 : index
        merged = between(slots[start].start_distance, slots[finish].end_distance)
        slots = slots.dup
        slots[start..finish] = [ merged ]
        slots
      end

      def extend_end(slot, finish)
        Slot.new(start_distance: slot.start_distance, end_distance: finish, terrain: slot.terrain,
                 name: slot.name, number: slot.number, height: slot.height, grade: slot.grade)
      end

      def extend_start(slot, start)
        Slot.new(start_distance: start, end_distance: slot.end_distance, terrain: slot.terrain,
                 name: slot.name, number: slot.number, height: slot.height, grade: slot.grade)
      end
    end
  end
end
