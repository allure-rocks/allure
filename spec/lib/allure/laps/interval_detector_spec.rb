# frozen_string_literal: true

require "rails_helper"

RSpec.describe Allure::Laps::IntervalDetector do
  # Irregular sampling, a value gap and a recording gap: everything the
  # sliding window has to get right against the plain definition.
  def points_for(count)
    start = Time.zone.parse("2026-08-23 06:00:00")
    time = start
    count.times.map do |index|
      time += [ 1, 2, 3, 7 ][index % 4]
      time += 120 if index == count / 2
      Allure::Segments::Point.new(
        index:,
        segment_index: index < count / 2 ? 0 : 1,
        segment_point_index: index,
        time:,
        elapsed_time: time - start,
        distance: index * 10.0,
        longitude: 6.4,
        latitude: 45.0,
        elevation: 100.0,
        speed: nil,
        heart_rate: 140,
        cadence: 80,
        power: (index % 9 == 4 ? nil : 150 + ((index * 37) % 120))
      )
    end
  end

  def brute_force_smoothing(points, half)
    values = points.map { |point| point.power&.to_f }
    points.map do |point|
      numbers = points.each_index.filter_map do |candidate|
        values[candidate] if (point.time - points[candidate].time).abs <= half
      end
      numbers.empty? ? nil : numbers.sum / numbers.length
    end
  end

  it "smooths with one sliding window, exactly like a rescan of every point" do
    points = points_for(400)
    detector = described_class.new(points:, enter: 230, exit: 200, min_duration: 20, min_recovery: 10, &:power)

    smoothed = detector.send(:smoothed_values)
    expected = brute_force_smoothing(points, described_class::SMOOTHING_SECONDS / 2.0)

    expect(smoothed.length).to eq(expected.length)
    smoothed.zip(expected).each do |actual, reference|
      if reference.nil?
        expect(actual).to be_nil
      else
        expect(actual).to be_within(1e-6).of(reference)
      end
    end
  end

  it "keeps the raw values when smoothing is off" do
    points = points_for(40)
    detector = described_class.new(points:, enter: 1, exit: 0, min_duration: 1, min_recovery: 1, smoothing_seconds: 0, &:power)

    expect(detector.send(:smoothed_values)).to eq(points.map { |point| point.power&.to_f })
  end

  it "opens a block after the minimum duration and closes it on the recovery" do
    start = Time.zone.parse("2026-08-23 06:00:00")
    values = Array.new(30, 100) + Array.new(60, 300) + Array.new(30, 100)
    points = values.each_with_index.map do |value, index|
      Allure::Segments::Point.new(
        index:, segment_index: 0, segment_point_index: index, time: start + index, elapsed_time: index,
        distance: index * 3.0, longitude: 6.4, latitude: 45.0, elevation: 100.0, speed: nil,
        heart_rate: nil, cadence: nil, power: value
      )
    end
    ranges = described_class.new(points:, enter: 250, exit: 200, min_duration: 10, min_recovery: 10, &:power).ranges

    expect(ranges.length).to eq(1)
    # The 20 s smoothing moves both edges a few seconds inside the raw step.
    expect(ranges.first.first).to be_between(28, 42)
    expect(ranges.first.last).to be_between(78, 92)
  end
end
