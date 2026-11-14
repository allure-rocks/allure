# frozen_string_literal: true

require "digest"
require "json"

module Allure
  module HeartRate
    # Five heart-rate zones from an account's profile (PLAN_HEART_RATE.md
    # §3.2). `bounds` are the lower edges of Z2…Z5 in percent of the maximum
    # (`max` basis) or of the reserve (`reserve`, Karvonen). Z1 has no floor
    # and Z5 no ceiling; thresholds are whole bpm, so slicing the per-bpm
    # histogram is exact.
    #
    # The load has a floor Z1 does not: ten points under the Z2 edge, in the
    # same basis — 50 % of the maximum with the default bounds, Edwards' own
    # lower limit. Time under it is shown in Z1 but carries no load.
    class Zones
      COUNT = 5
      BASES = %w[max reserve].freeze
      DEFAULT_BOUNDS = [ 60, 70, 80, 90 ].freeze
      BOUND_RANGE = (30..99)
      NAMES = %w[recovery endurance tempo threshold maximum].freeze
      LOAD_FLOOR_OFFSET = 10
      # Part of the fingerprint: a change in how zones or load are derived
      # makes every stored slice stale, so it is read again from the histogram.
      METHOD_VERSION = 2

      attr_reader :max, :rest, :basis, :bounds

      def initialize(max:, rest:, basis:, bounds:)
        @max = Integer(max)
        @basis = BASES.include?(basis.to_s) ? basis.to_s : "max"
        @rest = @basis == "reserve" ? Integer(rest) : nil
        @bounds = Array(bounds).map { Integer(it) }.freeze
        raise ArgumentError, "four bounds expected" unless @bounds.size == COUNT - 1
      end

      # The lower edge, in bpm, of Z2…Z5.
      def thresholds
        @thresholds ||= @bounds.map { bpm_at(it) }.freeze
      end

      # Whether every zone keeps at least one bpm once rounded.
      def distinct? = thresholds.each_cons(2).all? { |lower, upper| lower < upper }

      # One `[lower, upper]` pair per zone, inclusive, nil at the open ends.
      def ranges
        lowers = [ nil, *thresholds ]
        uppers = [ *thresholds.map { it - 1 }, nil ]
        lowers.zip(uppers)
      end

      # 1..5
      def zone_for(bpm)
        1 + thresholds.count { bpm >= it }
      end

      def load_floor_percent = @bounds.first - LOAD_FLOOR_OFFSET

      # The lowest bpm that carries load.
      def load_floor = @load_floor ||= bpm_at(load_floor_percent)

      # Seconds in Z1…Z5 from a histogram indexed from `Histogram::RANGE.begin`.
      def slice(histogram)
        seconds = Array.new(COUNT, 0)
        each_reading(histogram) { |bpm, value| seconds[zone_for(bpm) - 1] += value }
        seconds
      end

      # Seconds under the load floor, all of them inside Z1.
      def below_floor_seconds(histogram)
        total = 0
        each_reading(histogram) { |bpm, value| total += value if bpm < load_floor }
        total
      end

      def fingerprint
        @fingerprint ||= Digest::SHA256.hexdigest(JSON.generate([ METHOD_VERSION, @basis, @max, @rest, @bounds ]))[0, 16]
      end

      private

      def bpm_at(percent)
        base = @basis == "reserve" ? @rest + (percent / 100.0 * (@max - @rest)) : percent / 100.0 * @max
        base.round
      end

      def each_reading(histogram)
        histogram.each_with_index do |value, index|
          next unless value.positive?

          yield Histogram.bpm_for(index), value
        end
      end
    end
  end
end
