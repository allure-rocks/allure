# frozen_string_literal: true

module Allure
  module Toponyms
    # Chooses the globally useful combination of intermediate route steps.
    # It considers hierarchy, coverage, prominence and spacing together rather
    # than greedily accepting the first nearby place.
    class Selector
      ENDPOINT_MARGIN_FRACTION = 0.08
      MIN_SPACING_FRACTION = 0.12
      MIN_SPACING_METRES = 3_000.0
      MAX_CANDIDATES = 32
      COVERAGE_BUCKETS = 12
      TYPE_WEIGHT = {
        "pass" => 100.0,
        "summit" => 90.0,
        "landmark" => 80.0,
        "city" => 75.0,
        "town" => 70.0,
        "viewpoint" => 65.0,
        "waterfall" => 60.0,
        "spring" => 55.0,
        "village" => 55.0,
        "cave" => 52.0,
        "hut" => 50.0,
        "route" => 45.0,
        "hamlet" => 42.0,
        "locality" => 40.0,
        "isolated_dwelling" => 38.0,
        "municipality" => 28.0,
        "neighbourhood" => 25.0,
        "suburb" => 20.0,
        "county" => 10.0,
        "state" => 5.0
      }.freeze
      SHORT_ROUTE_TYPE_WEIGHT = TYPE_WEIGHT.merge(
        "city" => 25.0,
        "town" => 35.0,
        "municipality" => 30.0,
        "village" => 60.0,
        "suburb" => 62.0,
        "neighbourhood" => 68.0,
        "route" => 70.0,
        "isolated_dwelling" => 72.0,
        "hamlet" => 75.0,
        "locality" => 80.0
      ).freeze
      SHORT_ROUTE_MAX_DISTANCE = 30_000.0

      def initialize(candidates:, total_distance:, start_name: nil, finish_name: nil)
        @candidates = candidates
        @total_distance = total_distance.to_f
        @endpoint_names = [ start_name, finish_name ].compact.map { normalize(it) }
      end

      def call
        eligible = eligible_candidates
        return [] if eligible.empty?

        avg_density = eligible.sum { |candidate| density_for(eligible, candidate) } / eligible.length.to_f
        return [] if effective_limit(avg_density).zero?

        winner = best_combination(eligible, effective_limit(avg_density), avg_density)
        Array(winner).sort_by { it.fetch(:distance) }.each_with_index.map do |candidate, index|
          candidate.slice(:distance, :elevation, :name, :kind).merge(rank: index + 1)
        end
      end

      private

      def effective_min_spacing(avg_density)
        if avg_density > 3
          [ 1_000.0, @total_distance * 0.08 ].max
        elsif avg_density > 1
          [ 2_000.0, @total_distance * 0.10 ].max
        else
          [ MIN_SPACING_METRES, @total_distance * MIN_SPACING_FRACTION ].max
        end
      end

      def effective_limit(avg_density)
        base = case @total_distance
        when 0...10_000 then 1
        when 10_000...30_000 then 2
        when 30_000..80_000 then 3
        else 4
        end
        if avg_density > 3
          [ base + 2, 5 ].min
        elsif avg_density > 1
          [ base + 1, 4 ].min
        else
          base
        end
      end

      def eligible_candidates
        margin = @total_distance * ENDPOINT_MARGIN_FRACTION
        @candidates.select do |candidate|
          distance = candidate.fetch(:distance)
          TYPE_WEIGHT.key?(candidate.fetch(:kind)) &&
            (candidate[:climb_summit] || (distance >= margin && distance <= @total_distance - margin)) &&
            !@endpoint_names.include?(normalize(candidate.fetch(:name)))
        end
      end

      def best_combination(candidates, count, avg_density)
        candidates = candidate_pool(candidates) if candidates.length > MAX_CANDIDATES
        spacing = effective_min_spacing(avg_density)
        winner = nil
        winner_key = nil
        1.upto([ count, candidates.length ].min) do |size|
          candidates.combination(size) do |combination|
            next unless valid_combination?(combination, spacing)

            key = combination_key(combination)
            winner, winner_key = combination, key if winner_key.nil? || (key <=> winner_key) == 1
          end
        end
        winner
      end

      def candidate_pool(candidates)
        return candidates if candidates.length <= MAX_CANDIDATES

        buckets = candidates.group_by do |candidate|
          [ (candidate.fetch(:distance) / @total_distance * COVERAGE_BUCKETS).floor, COVERAGE_BUCKETS - 1 ].min
        end
        distributed = buckets.values.flat_map { top_candidates(it, 2) }
        remaining = top_candidates(candidates - distributed, MAX_CANDIDATES - distributed.length)
        (distributed + remaining).sort_by { it.fetch(:distance) }
      end

      def top_candidates(candidates, count)
        candidates.sort_by do |candidate|
          [ -candidate_score(candidate), normalize(candidate.fetch(:name)) ]
        end.first(count)
      end

      def valid_combination?(combination, spacing)
        ordered = combination.sort_by { it.fetch(:distance) }
        return false if ordered.map { normalize(it.fetch(:name)) }.uniq.length != ordered.length

        return false if ordered.each_cons(2).any? { |left, right| right.fetch(:distance) - left.fetch(:distance) < spacing }

        ordered.combination(2).none? { |left, right| nested?(left, right) }
      end

      def nested?(left, right)
        left_name = normalize(left.fetch(:name))
        right_name = normalize(right.fetch(:name))
        left_ancestors = Array(left[:ancestors]).map { normalize(it) }
        right_ancestors = Array(right[:ancestors]).map { normalize(it) }
        left_ancestors.include?(right_name) || right_ancestors.include?(left_name)
      end

      def combination_key(combination)
        score = combination.sum { candidate_score(it) }
        distances = combination.sort_by { it.fetch(:distance) }.map { it.fetch(:distance) }
        # Prefer a fuller, well-distributed story when semantic scores tie.
        spread = distances.length < 2 ? 0.0 : distances.each_cons(2).map { it.last - it.first }.min
        [ score, combination.length, spread, combination.map { normalize(it.fetch(:name)) }.sort.reverse ]
      end

      def candidate_score(candidate)
        type_weight(candidate.fetch(:kind)) +
          (candidate[:climb_summit] ? 45.0 : 0.0) +
          (candidate[:near_center] ? 30.0 : 0.0) -
          (candidate[:center_distance] && !candidate[:near_center] ? 10.0 : 0.0) +
          [ candidate.fetch(:importance, 0).to_f * 100.0, 20.0 ].min +
          [ candidate.fetch(:coverage, 0).to_f / [ @total_distance, 1.0 ].max * 10.0, 5.0 ].min +
          [ candidate.fetch(:occurrences, 1).to_i - 1, 5 ].min
      end

      def type_weight(kind)
        weights = @total_distance <= SHORT_ROUTE_MAX_DISTANCE ? SHORT_ROUTE_TYPE_WEIGHT : TYPE_WEIGHT
        weights.fetch(kind)
      end

      def density_for(candidates, candidate)
        point = candidate.fetch(:distance)
        candidates.count { |other| (other.fetch(:distance) - point).abs <= 2_000 }
      end

      def normalize(name)
        I18n.transliterate(name.to_s).downcase.strip
      end
    end
  end
end
