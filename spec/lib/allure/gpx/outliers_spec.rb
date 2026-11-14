# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Gpx::Outliers do
  let(:started_at) { Time.zone.parse("2026-06-01 08:00:00 UTC") }
  let(:metres_per_latitude_degree) { 111_319.49 }

  def point(second, latitude, longitude = 6.0)
    Allure::Gpx::Point.new(time: started_at + second, latitude:, longitude:)
  end

  def north(latitude, metres)
    latitude + (metres / metres_per_latitude_degree)
  end

  describe ".filter" do
    it "removes an isolated displaced point" do
      points = (0..7).map { |index| point(index, north(45.0, index * 2.0)) }
      points[4] = point(4, north(45.0, 8.0), 6.0005)

      filtered = described_class.filter(points)

      expect(filtered.length).to eq(7)
      expect(filtered).not_to include(points[4])
    end

    it "keeps a genuine out-and-back recorded over a plausible duration" do
      points = [
        point(0, 45.0),
        point(60, north(45.0, 111.0)),
        point(120, 45.0)
      ]

      expect(described_class.filter(points)).to eq(points)
    end

    it "trims a leading cold-fix artifact" do
      points = [ point(0, 45.0) ]
      latitude = 45.0
      8.times do |index|
        latitude = north(latitude, 8.0)
        points << point(index + 1, latitude)
      end
      100.times do |index|
        latitude = north(latitude, 1.2)
        points << point(9 + index, latitude)
      end

      filtered = described_class.filter(points)

      expect(filtered.length).to eq(points.length - 8)
      expect(filtered.first).to eq(points[8])
    end

    it "trims a trailing stale-fix artifact" do
      points = [ point(0, 45.0) ]
      latitude = 45.0
      100.times do |index|
        latitude = north(latitude, 1.2)
        points << point(index + 1, latitude)
      end
      8.times do |index|
        latitude = north(latitude, 8.0)
        points << point(101 + index, latitude)
      end

      filtered = described_class.filter(points)

      expect(filtered.length).to eq(points.length - 8)
      expect(filtered.last).to eq(points[100])
    end

    it "keeps a genuine fast start" do
      points = (0..40).map { |index| point(index, north(45.0, index * 5.56)) }

      expect(described_class.filter(points)).to eq(points)
    end

    it "returns short tracks unchanged" do
      points = [ point(0, 45.0), point(1, north(45.0, 500.0)) ]

      expect(described_class.filter(points)).to eq(points)
    end
  end

  describe ".reject_interior_spikes" do
    # The contract the single pass must keep: remove the leftmost spike, then
    # rescan the survivors from the start.
    def restarting_rejection(points)
      loop do
        removal = nil
        points.each_cons(3).with_index do |(previous_point, current, following_point), index|
          next unless described_class.interior_spike?(previous_point, current, following_point)

          removal = index + 1
          break
        end
        break if removal.nil?

        points = points[0...removal] + points[(removal + 1)..]
      end
      points
    end

    def noisy_track(random, length)
      latitude = 45.0
      second = 0
      Array.new(length) do
        second += random.rand < 0.05 ? random.rand(20..40) : 1
        latitude = north(latitude, random.rand(0.5..4.0))
        offset = random.rand < 0.3 ? random.rand(-0.002..0.002) : 0.0
        point(second, latitude, 6.0 + offset)
      end
    end

    def zigzag_track(clean_count, zigzag_count)
      clean = (0...clean_count).map { |index| point(index, north(45.0, index * 3.0)) }
      base = north(45.0, clean_count * 3.0)
      zigzag = (0...zigzag_count).map do |index|
        point(clean_count + index, index.even? ? base : north(base, 111.0))
      end
      clean + zigzag
    end

    it "matches the restarting rejection on spiky tracks" do
      random = Random.new(20_261_024)

      12.times do
        points = noisy_track(random, 400)

        expect(described_class.reject_interior_spikes(points)).to eq(restarting_rejection(points))
      end
    end

    it "matches the restarting rejection on a zigzag" do
      points = zigzag_track(500, 1_500)

      expect(described_class.reject_interior_spikes(points)).to eq(restarting_rejection(points))
    end

    it "rejects a dense zigzag in linear work" do
      points = zigzag_track(25_000, 25_000)
      calls = 0
      allow(Allure::Gpx::Geo).to receive(:horizontal_distance).and_wrap_original do |original, *arguments|
        calls += 1
        original.call(*arguments)
      end

      filtered = described_class.reject_interior_spikes(points)

      expect(calls).to be <= 6 * points.length
      expect(filtered.first(25_000)).to eq(points.first(25_000))
      expect(filtered.length).to be < points.length
    end
  end
end
